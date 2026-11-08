#!/usr/bin/env python3
"""Backend of Settings → Startup & Services.

Startup entries are the exec lines of ~/.config/hypr/custom/execs.lua (the file the
shell's update never overwrites). Each `hl.exec_cmd("…")` / `os.execute("…")` line is
one entry; a line commented out with `--` is an entry that is off, which is the same
thing people do by hand. A comment line right above an entry is its name.

Every edit names the entry by line number *and* a hash of the line, so an edit made
against a stale listing (the file changed in an editor meanwhile) is refused instead of
landing on the wrong line. Writes keep the inode (truncate + write) and leave a backup.

Services are systemd units (.service/.timer) of the user or the system manager; "mine"
means the unit file lives where a person puts units by hand (~/.config/systemd/user,
/etc/systemd/system, /usr/local/lib/systemd/system) rather than where packages do.

Every command prints one JSON document on stdout.
"""

import argparse
import configparser
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

HOME = os.path.expanduser("~")
CONFIG = os.environ.get("XDG_CONFIG_HOME", os.path.join(HOME, ".config"))
EXECS = os.path.join(CONFIG, "hypr", "custom", "execs.lua")
BACKUP = os.path.join(CONFIG, "hypr", "custom", ".execs.lua.ii-backup")
AUTOSTART = os.path.join(CONFIG, "autostart")

ENTRY_RE = re.compile(r"^(?P<indent>\s*)(?P<off>--\s*)?(?P<fn>hl\.exec_cmd|os\.execute)\s*\((?P<arg>.*)\)\s*;?\s*(?P<trail>--.*)?$")
COMMENT_RE = re.compile(r"^\s*--(?!\[\[)\s?(?P<text>.*)$")
START_RE = re.compile(r"""hl\.on\(\s*["']hyprland\.start["']""")


def out(obj):
    json.dump(obj, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


def fail(msg, code=1):
    out({"ok": False, "error": msg})
    sys.exit(code)


# ── Lua string literals ─────────────────────────────────────────────────────────────

LUA_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "a": "\a", "b": "\b", "f": "\f", "v": "\v", "\n": "\n"}


def parse_lua_string(src):
    """The value of `src` when it is exactly one Lua string literal, else None."""
    s = src.strip()
    if len(s) >= 2 and s[0] in "\"'":
        q = s[0]
        i, buf = 1, []
        while i < len(s):
            c = s[i]
            if c == "\\":
                i += 1
                if i >= len(s):
                    return None
                e = s[i]
                if e in LUA_ESCAPES:
                    buf.append(LUA_ESCAPES[e])
                elif e.isdigit():
                    m = re.match(r"\d{1,3}", s[i:])
                    buf.append(chr(int(m.group(0))))
                    i += len(m.group(0)) - 1
                else:
                    return None
            elif c == q:
                return "".join(buf) if i == len(s) - 1 else None
            else:
                buf.append(c)
            i += 1
        return None
    m = re.fullmatch(r"\[(=*)\[(.*)\]\1\]", s, re.S)
    if m:
        return m.group(2)
    return None


def lua_quote(value):
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


# ── names ──────────────────────────────────────────────────────────────────────────

WRAPPERS = {"bash", "sh", "zsh", "env", "exec", "nohup", "setsid", "uwsm", "app", "--", "-c", "sleep", "&&", "systemd-run"}


def derive_name(cmd):
    """A readable name from a command: the program that actually runs."""
    text = cmd.strip()
    inner = re.search(r"""(?:bash|sh|zsh)\s+-c\s+(['"])(.*)\1""", text)
    if inner:
        text = inner.group(2)
    for part in re.split(r"&&|;|\|\|", text):
        words = part.strip().split()
        idx = 0
        while idx < len(words):
            w = words[idx]
            if w in WRAPPERS or "=" in w and not w.startswith("/") or re.fullmatch(r"[\d.]+[smh]?", w) or w.startswith("-"):
                idx += 1
                continue
            if w in ("flatpak",) and idx + 2 < len(words) and words[idx + 1] == "run":
                return words[idx + 2].split(".")[-1]
            if w == "hyprctl" and "plugin" in words:
                return os.path.basename(words[-1]).removesuffix(".so")
            return os.path.basename(w.strip("'\""))
    return text[:40]


def line_hash(line):
    return hashlib.sha1(line.rstrip("\n").encode()).hexdigest()[:12]


# ── execs.lua ──────────────────────────────────────────────────────────────────────

def read_lines():
    if not os.path.exists(EXECS):
        return []
    with open(EXECS, encoding="utf-8") as f:
        return f.read().split("\n")


def write_lines(lines):
    os.makedirs(os.path.dirname(EXECS), exist_ok=True)
    if os.path.exists(EXECS):
        shutil.copyfile(EXECS, BACKUP)
    text = "\n".join(lines)
    if not text.endswith("\n"):
        text += "\n"
    # same inode: watchers on the file keep working
    with open(EXECS, "r+" if os.path.exists(EXECS) else "w", encoding="utf-8") as f:
        f.seek(0)
        f.write(text)
        f.truncate()


def start_block(lines):
    """(first, last) line indices inside the hyprland.start handler, or None."""
    for i, l in enumerate(lines):
        if START_RE.search(l) and not COMMENT_RE.match(l):
            for j in range(i + 1, len(lines)):
                if re.match(r"^end\s*\)\s*$", lines[j]):
                    return i, j
            return None
    return None


def parse_entries(lines):
    block = start_block(lines)
    entries = []
    for i, line in enumerate(lines):
        m = ENTRY_RE.match(line)
        if not m:
            continue
        value = parse_lua_string(m.group("arg"))
        name, label_line = "", -1
        j = i - 1
        if j >= 0:
            c = COMMENT_RE.match(lines[j])
            if c and not ENTRY_RE.match(lines[j]) and c.group("text").strip() and "(" not in c.group("text")[:1]:
                name, label_line = c.group("text").strip(), j
        cmd = value if value is not None else m.group("arg").strip()
        entries.append({
            "line": i,
            "hash": line_hash(line),
            "labelLine": label_line,
            "enabled": m.group("off") is None,
            "kind": "lua" if m.group("fn") == "os.execute" else "exec",
            "editable": value is not None,
            "atStart": bool(block and block[0] < i < block[1]),
            "name": name,
            "derivedName": derive_name(cmd),
            "command": cmd,
        })
    return entries


def find(lines, line, h):
    if line < 0 or line >= len(lines) or line_hash(lines[line]) != h:
        fail("The file changed since it was read. Refresh and try again.", 3)
    m = ENTRY_RE.match(lines[line])
    if not m:
        fail("That line is no longer a startup entry.", 3)
    return m


def label_index(lines, line):
    j = line - 1
    if j >= 0:
        c = COMMENT_RE.match(lines[j])
        if c and not ENTRY_RE.match(lines[j]) and c.group("text").strip():
            return j
    return -1


def cmd_list(_args):
    lines = read_lines()
    out({"ok": True, "path": EXECS, "exists": os.path.exists(EXECS), "hasStartBlock": start_block(lines) is not None,
         "entries": parse_entries(lines), "autostart": list_autostart()})


def build_line(indent, fn, cmd, enabled):
    return f"{indent}{'' if enabled else '-- '}{fn}({lua_quote(cmd)})"


def cmd_add(args):
    lines = read_lines()
    block = start_block(lines)
    cmd = args.command
    if args.delay and args.delay > 0:
        cmd = f"sleep {args.delay} && {cmd}"
    new = []
    if args.name:
        new.append(f"    -- {args.name.strip()}")
    new.append(build_line("    ", "hl.exec_cmd", cmd, True))
    if block is None:
        if lines and lines[-1].strip() == "":
            lines.pop()
        if lines:
            lines.append("")
        lines += ["-- Startup entries: managed from Settings → Startup & Services, safe to edit by hand",
                  'hl.on("hyprland.start", function()'] + new + ["end)"]
    else:
        end = block[1]
        if end - 1 > block[0] and lines[end - 1].strip() != "":
            new.insert(0, "")
        lines[end:end] = new
    write_lines(lines)
    out({"ok": True})


def cmd_toggle(args):
    lines = read_lines()
    m = find(lines, args.line, args.hash)
    enabled = m.group("off") is not None if args.enabled is None else args.enabled == "on"
    rest = lines[args.line][m.end("off"):] if m.group("off") else lines[args.line][len(m.group("indent")):]
    lines[args.line] = m.group("indent") + ("" if enabled else "-- ") + rest
    write_lines(lines)
    out({"ok": True, "enabled": enabled})


def cmd_edit(args):
    lines = read_lines()
    m = find(lines, args.line, args.hash)
    if parse_lua_string(m.group("arg")) is None:
        fail("This entry is built from Lua code. Edit it in the file.")
    trail = (" " + m.group("trail")) if m.group("trail") else ""
    lines[args.line] = build_line(m.group("indent"), m.group("fn"), args.command, m.group("off") is None) + trail
    lab = label_index(lines, args.line)
    name = (args.name or "").strip()
    if lab >= 0:
        if name:
            lines[lab] = f"{m.group('indent')}-- {name}"
        else:
            del lines[lab]
    elif name:
        lines.insert(args.line, f"{m.group('indent')}-- {name}")
    write_lines(lines)
    out({"ok": True})


def cmd_remove(args):
    lines = read_lines()
    find(lines, args.line, args.hash)
    lab = label_index(lines, args.line)
    # the label goes with it unless it heads a group (the next line is another entry)
    del lines[args.line]
    at = args.line
    if lab >= 0 and not (at < len(lines) and ENTRY_RE.match(lines[at])):
        del lines[lab]
        at = lab
    # no blank line left hanging before the handler's `end)`
    if 0 < at < len(lines) and lines[at - 1].strip() == "" and re.match(r"^end\s*\)", lines[at]):
        del lines[at - 1]
    write_lines(lines)
    out({"ok": True})


# ── XDG autostart (not run by Hyprland) ─────────────────────────────────────────────

def list_autostart():
    items = []
    if not os.path.isdir(AUTOSTART):
        return items
    for fn in sorted(os.listdir(AUTOSTART)):
        if not fn.endswith(".desktop"):
            continue
        cp = configparser.RawConfigParser(strict=False, interpolation=None)
        try:
            cp.read(os.path.join(AUTOSTART, fn), encoding="utf-8")
            d = cp["Desktop Entry"]
        except Exception:
            continue
        if d.get("Hidden", "false").lower() == "true":
            continue
        only = d.get("OnlyShowIn", "")
        exec_ = re.sub(r"\s*%[a-zA-Z]", "", d.get("Exec", "")).strip()
        if not exec_:
            continue
        items.append({"file": fn, "name": d.get("Name", fn[:-8]), "icon": d.get("Icon", ""), "command": exec_,
                      "onlyShowIn": only})
    return items


# ── systemd ────────────────────────────────────────────────────────────────────────

def mine_dirs(scope):
    if scope == "user":
        return [os.path.join(CONFIG, "systemd", "user"), os.path.join(HOME, ".local", "share", "systemd", "user")]
    return ["/etc/systemd/system", "/usr/local/lib/systemd/system"]


def sysctl(scope, *a):
    return ["systemctl"] + (["--user"] if scope == "user" else []) + ["--no-pager"] + list(a)


def run_json(cmd):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
        return json.loads(r.stdout or "[]")
    except Exception:
        return []


def unit_description(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                if line.strip().startswith("Description="):
                    return line.split("=", 1)[1].strip()
    except OSError:
        pass
    return ""


def cmd_units(args):
    scope = args.scope
    files = run_json(sysctl(scope, "list-unit-files", "--type=service,timer", "--output=json"))
    loaded = run_json(sysctl(scope, "list-units", "--type=service,timer", "--all", "--output=json"))
    units = {}
    for f in files:
        name = os.path.basename(f.get("unit_file", ""))
        if not name or name.endswith("@.service") or name.endswith("@.timer"):
            continue
        units[name] = {"name": name, "fileState": f.get("state", ""), "preset": f.get("preset") or "",
                       "load": "", "active": "inactive", "sub": "dead", "description": ""}
    for u in loaded:
        name = u.get("unit", "")
        if not name:
            continue
        e = units.setdefault(name, {"name": name, "fileState": "", "preset": ""})
        e.update({"load": u.get("load", ""), "active": u.get("active", ""), "sub": u.get("sub", ""),
                  "description": u.get("description", "")})
    mine, overridden = {}, set()
    for d in mine_dirs(scope):
        if not os.path.isdir(d):
            continue
        for fn in os.listdir(d):
            p = os.path.join(d, fn)
            if fn.endswith((".service", ".timer")) and os.path.isfile(p) and not os.path.islink(p):
                mine.setdefault(fn, p)
            elif fn.endswith((".service.d", ".timer.d")) and os.path.isdir(p) and any(x.endswith(".conf") for x in os.listdir(p)):
                overridden.add(fn[:-2])
    result = []
    for name, e in units.items():
        if e.get("load") == "not-found" and name not in mine:
            continue
        e["mine"] = name in mine
        e["path"] = mine.get(name, "")
        e["overridden"] = name in overridden
        e["type"] = "timer" if name.endswith(".timer") else "service"
        if e["mine"] and not e.get("description"):
            e["description"] = unit_description(e["path"])
        result.append(e)
    result.sort(key=lambda e: (not e["mine"], e["name"].lower()))
    out({"ok": True, "scope": scope, "units": result})


SHOW_PROPS = ["Id", "Description", "LoadState", "ActiveState", "SubState", "UnitFileState", "UnitFilePreset",
              "FragmentPath", "DropInPaths", "MainPID", "MemoryCurrent", "ActiveEnterTimestamp",
              "InactiveEnterTimestamp", "Result", "ExecMainStatus", "NextElapseUSecRealtime", "LastTriggerUSec",
              "Triggers", "TriggeredBy", "WantedBy", "Restart", "ExecStart", "NRestarts", "CPUUsageNSec"]


def cmd_show(args):
    scope, unit = args.scope, args.unit
    r = subprocess.run(sysctl(scope, "show", unit, "-p", ",".join(SHOW_PROPS)), capture_output=True, text=True)
    props = {}
    for line in r.stdout.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            props[k] = v
    path = props.get("FragmentPath", "")
    content, writable = "", False
    if path and os.path.isfile(path):
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                content = f.read()
        except OSError:
            pass
        writable = os.access(path, os.W_OK)
    dropins = [p for p in props.get("DropInPaths", "").split() if p]
    jcmd = ["journalctl", "--no-pager", "-o", "short", "-n", str(args.lines)]
    jcmd += ["--user-unit", unit] if scope == "user" else ["-u", unit]
    try:
        j = subprocess.run(jcmd, capture_output=True, text=True, timeout=10)
        log = j.stdout.strip()
    except Exception:
        log = ""
    mine = any(path.startswith(d + "/") for d in mine_dirs(scope)) if path else False
    out({"ok": True, "scope": scope, "unit": unit, "props": props, "path": path, "content": content,
         "writable": writable, "mine": mine, "dropins": dropins, "log": log})


def cmd_save_unit(args):
    content = sys.stdin.read()
    path = args.path
    scope = args.scope
    if not re.search(r"\.(service|timer)$", path) or not os.path.isabs(path):
        fail("Not a unit file path.")
    if scope == "user" or os.access(path, os.W_OK):
        with open(path, "r+" if os.path.exists(path) else "w", encoding="utf-8") as f:
            f.write(content)
            f.truncate()
        subprocess.run(sysctl(scope, "daemon-reload"))
        out({"ok": True})
        return
    r = subprocess.run(["pkexec", "sh", "-c", 'cat > "$1" && systemctl daemon-reload', "sh", path],
                       input=content, text=True, capture_output=True)
    if r.returncode != 0:
        fail("Not saved: authentication was refused or the write failed." if r.returncode in (126, 127)
             else (r.stderr.strip() or "Write failed."))
    out({"ok": True})


def cmd_action(args):
    verb = args.verb
    if verb not in ("start", "stop", "restart", "enable", "disable", "enable-now", "disable-now", "unmask"):
        fail("Unknown action.")
    a = [verb.split("-")[0], args.unit] + (["--now"] if verb.endswith("-now") else [])
    r = subprocess.run(sysctl(args.scope, *a), capture_output=True, text=True)
    if r.returncode != 0:
        msg = r.stderr.strip().splitlines()
        fail(msg[-1] if msg else "systemctl failed.")
    out({"ok": True})


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list")
    a = sub.add_parser("add")
    a.add_argument("--name", default="")
    a.add_argument("--command", required=True)
    a.add_argument("--delay", type=int, default=0)
    for n in ("toggle", "edit", "remove"):
        s = sub.add_parser(n)
        s.add_argument("--line", type=int, required=True)
        s.add_argument("--hash", required=True)
        if n == "toggle":
            s.add_argument("--enabled", choices=["on", "off"])
        if n == "edit":
            s.add_argument("--name", default="")
            s.add_argument("--command", required=True)
    u = sub.add_parser("units")
    u.add_argument("--scope", choices=["user", "system"], default="user")
    s = sub.add_parser("show")
    s.add_argument("--scope", choices=["user", "system"], default="user")
    s.add_argument("--unit", required=True)
    s.add_argument("--lines", type=int, default=80)
    s = sub.add_parser("save-unit")
    s.add_argument("--scope", choices=["user", "system"], default="user")
    s.add_argument("--path", required=True)
    s = sub.add_parser("action")
    s.add_argument("--scope", choices=["user", "system"], default="user")
    s.add_argument("--unit", required=True)
    s.add_argument("--verb", required=True)
    args = p.parse_args()
    {"list": cmd_list, "add": cmd_add, "toggle": cmd_toggle, "edit": cmd_edit, "remove": cmd_remove,
     "units": cmd_units, "show": cmd_show, "save-unit": cmd_save_unit, "action": cmd_action}[args.cmd](args)


if __name__ == "__main__":
    main()
