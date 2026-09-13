#!/usr/bin/env python3
"""Targeted edits to voxtype's config.toml, preserving everything else.

Voxtype owns a large, heavily commented config file, and its own CLI can only
set `engine` (`voxtype config set`) and the Whisper model (`voxtype setup model
--set`). The shell needs a handful of other keys — the built-in hotkey off (the
compositor owns the key), the state file on (the shell reads it), the output
mode, the spoken language — and rewriting the file from a template to get them,
the way other integrations do, would silently discard whatever the user tuned by
hand. So this edits individual assignments in place instead: comments, ordering,
unrelated tables and unknown keys all survive.

    voxtype_config.py read
    voxtype_config.py set whisper.language=fr output.mode=type hotkey.enabled=false

`read` prints the settings the shell cares about as JSON. `set` applies each
`table.key=value` pair and rewrites the file atomically, but only after the
result has been re-parsed — a botched edit leaves the original file untouched.
With no config present at all, `voxtype setup` is asked to write its own default
first; hand-rolling one risks missing a field voxtype requires.

Values are typed by shape: `true`/`false` are booleans, digits are integers,
a bracketed list becomes a TOML array (`whisper.language=[en,fr]`, which voxtype
reads as constrained auto-detection), and anything else is a string.
"""

import json
import os
import re
import subprocess
import sys
import tempfile
import tomllib

CONFIG_PATH = os.path.join(
    os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"),
    "voxtype", "config.toml")

# voxtype's config has required fields with no serde default (max_duration_secs
# among them), and the set of them moves between releases — a hand-written seed
# that misses one produces a daemon that refuses to start. `voxtype setup` writes
# a complete, valid, commented config and downloads nothing, so seeding is
# delegated to it rather than duplicated here.
def seed_config():
    try:
        result = subprocess.run(
            ["voxtype", "setup", "--quiet", "--no-post-install"],
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=120)
    except FileNotFoundError:
        print("voxtype is not installed, cannot create a config", file=sys.stderr)
        return False
    except subprocess.TimeoutExpired:
        print("voxtype setup did not finish in time", file=sys.stderr)
        return False
    if not os.path.exists(CONFIG_PATH):
        print("voxtype setup did not write %s: %s"
              % (CONFIG_PATH, result.stderr.decode(errors="replace").strip()), file=sys.stderr)
        return False
    return True


# What `read` reports back, as (table, key) -> name in the emitted JSON.
READ_KEYS = {
    ("", "state_file"): "stateFile",
    ("hotkey", "enabled"): "hotkeyEnabled",
    ("whisper", "model"): "model",
    ("whisper", "language"): "language",
    ("whisper", "translate"): "translate",
    ("audio", "max_duration_secs"): "maxDurationSecs",
    ("audio", "pause_media"): "pauseMedia",
    ("audio.feedback", "enabled"): "soundFeedback",
    ("output", "mode"): "outputMode",
    ("output", "auto_submit"): "autoSubmit",
}


def quote(text):
    """A TOML basic string. Escapes what a basic string may not contain raw."""
    escaped = text.replace("\\", "\\\\").replace('"', '\\"')
    escaped = escaped.replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")
    return '"%s"' % escaped


def format_value(raw):
    """
    TOML literal for a value given on the command line.

    Arrays have to be asked for with brackets (`[en,fr]`). Inferring them from
    a comma instead is tempting and wrong: a prompt like "Bonjour, voici un
    texte" is prose, and turning it into an array of fragments produces a file
    that parses cleanly and that voxtype then rejects at load.
    """
    stripped = raw.strip()
    lowered = stripped.lower()
    if lowered in ("true", "false"):
        return lowered
    if re.fullmatch(r"-?\d+", stripped):
        return stripped
    if len(stripped) >= 2 and stripped[0] == "[" and stripped[-1] == "]":
        parts = [p.strip() for p in stripped[1:-1].split(",") if p.strip()]
        return "[" + ", ".join(quote(p) for p in parts) + "]"
    return quote(raw)


def table_of(line, current):
    """The table a line belongs to, given the table the previous line was in."""
    header = re.match(r"\s*\[([^\[\]]+)\]\s*(?:#.*)?$", line)
    if header:
        return header.group(1).strip()
    if re.match(r"\s*\[\[", line):
        return None  # array-of-tables: nothing we set lives in one
    return current


def trailing_comment(line):
    """The ` # ...` tail of an assignment, if it has one outside of a string."""
    in_string = False
    escaped = False
    for index, char in enumerate(line):
        if escaped:
            escaped = False
            continue
        if char == "\\":
            escaped = True
            continue
        if char == '"':
            in_string = not in_string
            continue
        if char == "#" and not in_string:
            return "  " + line[index:].strip()
    return ""


def apply_edit(lines, table, key, value):
    """Set one key, preferring the assignment already in the file."""
    active = re.compile(r"\s*%s\s*=" % re.escape(key))
    commented = re.compile(r"\s*#\s*%s\s*=" % re.escape(key))
    current = ""
    commented_at = None
    table_ends_at = None

    for index, line in enumerate(lines):
        current = table_of(line, current)
        if current is None:
            continue
        if current != table:
            continue
        # Track the table's last real line so a missing key can be appended to
        # it rather than to the end of the file, where it would land in
        # whatever table happens to come last. Blank lines are skipped so the
        # new key lands against the existing ones instead of after the gap
        # that separates this table from the next.
        if line.strip() and not re.match(r"\s*\[", line):
            table_ends_at = index
        if active.match(line):
            lines[index] = "%s = %s%s" % (key, value, trailing_comment(line))
            return lines
        if commented_at is None and commented.match(line):
            commented_at = index

    if commented_at is not None:
        # The upstream template documents most keys as commented-out examples.
        # Activating one directly below its comment keeps that documentation.
        lines.insert(commented_at + 1, "%s = %s" % (key, value))
        return lines

    if table_ends_at is not None:
        lines.insert(table_ends_at + 1, "%s = %s" % (key, value))
        return lines

    if table == "":
        # Top-level keys must precede the first table header, or TOML reads
        # them as belonging to that table.
        for index, line in enumerate(lines):
            if re.match(r"\s*\[", line):
                lines.insert(index, "%s = %s" % (key, value))
                lines.insert(index + 1, "")
                return lines
        lines.append("%s = %s" % (key, value))
        return lines

    while lines and not lines[-1].strip():
        lines.pop()
    lines.extend(["", "[%s]" % table, "%s = %s" % (key, value)])
    return lines


def read_config():
    try:
        with open(CONFIG_PATH, "rb") as handle:
            return tomllib.load(handle)
    except FileNotFoundError:
        return None
    except tomllib.TOMLDecodeError as error:
        print("config.toml is not valid TOML: %s" % error, file=sys.stderr)
        return None


def lookup(data, table, key):
    node = data
    if table:
        for part in table.split("."):
            if not isinstance(node, dict) or part not in node:
                return None
            node = node[part]
    if not isinstance(node, dict):
        return None
    return node.get(key)


def command_read():
    data = read_config()
    result = {"exists": data is not None, "path": CONFIG_PATH}
    if data is not None:
        for (table, key), name in READ_KEYS.items():
            value = lookup(data, table, key)
            if value is not None:
                result[name] = value
    print(json.dumps(result))
    return 0


def command_set(pairs):
    if not os.path.exists(CONFIG_PATH) and not seed_config():
        return 1

    with open(CONFIG_PATH, "r") as handle:
        lines = handle.read().split("\n")

    for pair in pairs:
        if "=" not in pair:
            print("expected table.key=value, got %r" % pair, file=sys.stderr)
            return 2
        path, raw = pair.split("=", 1)
        path = path.strip()
        table, _, key = path.rpartition(".")
        if not key:
            print("expected table.key=value, got %r" % pair, file=sys.stderr)
            return 2
        lines = apply_edit(lines, table, key, format_value(raw))

    text = "\n".join(lines)
    if not text.endswith("\n"):
        text += "\n"

    # Parse the result before it replaces anything. A config the daemon cannot
    # read would take dictation down until someone edited the file by hand.
    try:
        tomllib.loads(text)
    except tomllib.TOMLDecodeError as error:
        print("refusing to write, edit produced invalid TOML: %s" % error, file=sys.stderr)
        return 1

    directory = os.path.dirname(CONFIG_PATH)
    handle = tempfile.NamedTemporaryFile("w", dir=directory, delete=False)
    try:
        handle.write(text)
        handle.flush()
        os.fsync(handle.fileno())
        handle.close()
        os.chmod(handle.name, 0o600)
        os.replace(handle.name, CONFIG_PATH)
    except Exception:
        os.unlink(handle.name)
        raise
    print("ok")
    return 0


def main(argv):
    if len(argv) < 2 or argv[1] not in ("read", "set"):
        print(__doc__, file=sys.stderr)
        return 2
    if argv[1] == "read":
        return command_read()
    return command_set(argv[2:])


if __name__ == "__main__":
    sys.exit(main(sys.argv))
