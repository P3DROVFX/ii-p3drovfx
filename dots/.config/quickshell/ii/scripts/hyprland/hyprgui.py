#!/usr/bin/env python3
"""Read and write the Quickshell-managed region of a ~/.config/hypr/custom/*.lua file.

Settings -> Hyprland owns a fenced block at the end of each custom Lua file:

    -- >>> quickshell:managed:begin v1 ...
    hl.config({ input = { kb_layout = "fr" } })   --@k input:kb_layout
    -- <<< quickshell:managed:end

Everything outside the fence is hand-written and is preserved byte for byte.
The fence sits at the end of the file so its statements run after the
hand-written ones in the same file and therefore win.

Commands
    read   --file F              JSON: managed entries + recognisable unmanaged ones
    write  --file F --json -     replace the region from a JSON document on stdin
    write  --file F --json - --dry-run    print a unified diff instead of writing
    strip  --file F              remove the region entirely

The desired state arrives on stdin, never on argv: window-rule patterns contain
$ | \\ and quotes, and none of that should ever reach a shell.
"""

import json
import os
import re
import sys
import time

# The GUI starts this script once per read and once per write, so how long it takes to start
# is part of how long a setting takes to apply. argparse, difflib, shutil, subprocess and
# tempfile together cost more than everything this script actually does, and none of them are
# needed by a plain write - so the options are described as data at the bottom and parsed by
# hand, and the rest are imported where they are used.

REGION_VERSION = 1
BEGIN_RE = re.compile(r'^\s*--\s*>>>\s*quickshell:managed:begin(?:\s+v(\d+))?')
END_RE = re.compile(r'^\s*--\s*<<<\s*quickshell:managed:end')
BEGIN_LINE = ("-- >>> quickshell:managed:begin v%d - written by Settings -> Hyprland. "
              "Edits here are overwritten; put your own Lua above.\n" % REGION_VERSION)
END_LINE = "-- <<< quickshell:managed:end\n"

DEFAULT_CUSTOM_DIR = os.path.expanduser("~/.config/hypr/custom")
BACKUP_DIR = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
                          "quickshell", "hyprland-backups")
BACKUP_KEEP = 20
ALIGN_COLUMN = 78

# ---------------------------------------------------------------------------
# Lua lexing
# ---------------------------------------------------------------------------

NAME_RE = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')
NUMBER_RE = re.compile(r'0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?')
IDENT_RE = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*$')
LUA_KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if",
    "in", "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while",
}


class Token:
    __slots__ = ("kind", "value", "start", "end")

    def __init__(self, kind, value, start, end):
        self.kind = kind          # name | number | string | op
        self.value = value        # decoded value for strings, source text otherwise
        self.start = start
        self.end = end

    def __repr__(self):
        return "Token(%s, %r)" % (self.kind, self.value)


def _skip_long_bracket(text, i):
    """If text[i] opens a [=*[ long bracket, return the index past its close."""
    if text[i] != '[':
        return None
    j = i + 1
    level = 0
    while j < len(text) and text[j] == '=':
        level += 1
        j += 1
    if j >= len(text) or text[j] != '[':
        return None
    close = ']' + '=' * level + ']'
    end = text.find(close, j + 1)
    return len(text) if end < 0 else end + len(close)


def _skip_string(text, i):
    """text[i] is a quote. Return the index past the closing quote."""
    quote = text[i]
    j = i + 1
    while j < len(text):
        c = text[j]
        if c == '\\':
            j += 2
            continue
        if c == quote:
            return j + 1
        j += 1
    return len(text)


def _skip_comment(text, i):
    """text[i:i+2] == '--'. Return the index past the comment."""
    j = _skip_long_bracket(text, i + 2)
    if j is not None:
        return j
    nl = text.find('\n', i)
    return len(text) if nl < 0 else nl


_ESCAPES = {'a': '\a', 'b': '\b', 'f': '\f', 'n': '\n', 'r': '\r', 't': '\t', 'v': '\v',
            '\\': '\\', '"': '"', "'": "'", '\n': '\n'}


def _decode_string(raw):
    """raw includes its delimiters."""
    if raw.startswith('['):
        m = re.match(r'^\[(=*)\[(.*)\]\1\]$', raw, re.S)
        body = m.group(2) if m else raw
        return body[1:] if body.startswith('\n') else body
    body = raw[1:-1]
    out = []
    i = 0
    while i < len(body):
        c = body[i]
        if c != '\\':
            out.append(c)
            i += 1
            continue
        i += 1
        if i >= len(body):
            break
        e = body[i]
        if e in _ESCAPES:
            out.append(_ESCAPES[e])
            i += 1
        elif e == 'x':
            out.append(chr(int(body[i + 1:i + 3], 16)))
            i += 3
        elif e == 'z':
            i += 1
            while i < len(body) and body[i].isspace():
                i += 1
        elif e.isdigit():
            m = re.match(r'\d{1,3}', body[i:])
            out.append(chr(int(m.group(0))))
            i += len(m.group(0))
        else:
            out.append(e)
            i += 1
    return ''.join(out)


def tokenize(text):
    tokens = []
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c.isspace():
            i += 1
            continue
        if text.startswith('--', i):
            i = _skip_comment(text, i)
            continue
        if c in '"\'':
            j = _skip_string(text, i)
            tokens.append(Token('string', _decode_string(text[i:j]), i, j))
            i = j
            continue
        if c == '[':
            j = _skip_long_bracket(text, i)
            if j is not None:
                tokens.append(Token('string', _decode_string(text[i:j]), i, j))
                i = j
                continue
        m = NAME_RE.match(text, i)
        if m:
            tokens.append(Token('name', m.group(0), i, m.end()))
            i = m.end()
            continue
        m = NUMBER_RE.match(text, i)
        if m:
            tokens.append(Token('number', m.group(0), i, m.end()))
            i = m.end()
            continue
        tokens.append(Token('op', c, i, i + 1))
        i += 1
    return tokens


def split_code_and_comment(line):
    """Split a source line into (code, comment) without breaking on -- inside a string."""
    i = 0
    n = len(line)
    while i < n:
        c = line[i]
        if c in '"\'':
            i = _skip_string(line, i)
            continue
        if c == '[':
            j = _skip_long_bracket(line, i)
            if j is not None:
                i = j
                continue
        if line.startswith('--', i):
            return line[:i], line[i:]
        i += 1
    return line, ''


# ---------------------------------------------------------------------------
# Lua value parsing
# ---------------------------------------------------------------------------

class Parser:
    def __init__(self, tokens, text):
        self.t = tokens
        self.text = text
        self.i = 0
        # "a:b:c" -> (start, stop) of that assignment in `text`. Only filled for keys, so a
        # caller can point at the one line that sets a key instead of the whole call.
        self.spans = {}

    def peek(self, offset=0):
        j = self.i + offset
        return self.t[j] if j < len(self.t) else None

    def at_op(self, op, offset=0):
        tok = self.peek(offset)
        return tok is not None and tok.kind == 'op' and tok.value == op

    def take(self):
        tok = self.peek()
        self.i += 1
        return tok

    def expect_op(self, op):
        if not self.at_op(op):
            raise ValueError("expected %r" % op)
        return self.take()

    def parse_value(self, path=()):
        tok = self.peek()
        if tok is None:
            raise ValueError("unexpected end of value")
        if tok.kind == 'op' and tok.value == '{':
            return self.parse_table(path)
        if tok.kind == 'string' and not self._continues_expression(1):
            self.take()
            return tok.value
        if tok.kind == 'number' and not self._continues_expression(1):
            self.take()
            return _lua_number(tok.value)
        if tok.kind == 'op' and tok.value == '-':
            nxt = self.peek(1)
            if nxt is not None and nxt.kind == 'number' and not self._continues_expression(2):
                self.take()
                self.take()
                return -_lua_number(nxt.value)
        if tok.kind == 'name' and tok.value in ('true', 'false') and not self._continues_expression(1):
            self.take()
            return tok.value == 'true'
        if tok.kind == 'name' and tok.value == 'nil' and not self._continues_expression(1):
            self.take()
            return None
        return self.parse_raw()

    def _continues_expression(self, offset):
        """True when the token at offset keeps the current value going (a .. b, f(x), t.k)."""
        tok = self.peek(offset)
        if tok is None:
            return False
        if tok.kind == 'op' and tok.value in ',;}])=':
            return False
        return True

    def parse_raw(self):
        """Consume tokens up to the next top-level , ; or } and keep the source verbatim."""
        start = self.peek().start
        depth = 0
        end = start
        while True:
            tok = self.peek()
            if tok is None:
                break
            if tok.kind == 'op':
                if tok.value in '({[':
                    depth += 1
                elif tok.value in ')}]':
                    if depth == 0:
                        break
                    depth -= 1
                elif tok.value in ',;' and depth == 0:
                    break
            end = tok.end
            self.take()
        return {"__raw": self.text[start:end].strip()}

    def parse_table(self, path=()):
        self.expect_op('{')
        array = []
        hash_ = {}
        order = []
        while True:
            if self.at_op('}'):
                self.take()
                break
            if self.peek() is None:
                raise ValueError("unterminated table")
            if self.at_op(',') or self.at_op(';'):
                self.take()
                continue
            key = None
            entry_start = self.peek().start
            if self.at_op('['):
                self.take()
                key = self.parse_value()
                self.expect_op(']')
                self.expect_op('=')
            else:
                tok = self.peek()
                if tok is not None and tok.kind == 'name' and self.at_op('=', 1):
                    key = tok.value
                    self.take()
                    self.take()
            child = path + (str(key),) if key is not None else path
            value = self.parse_value(child)
            if key is None:
                array.append(value)
            else:
                key = str(key)
                if key not in hash_:
                    order.append(key)
                hash_[key] = value
                self.spans[":".join(child)] = (entry_start, self.t[self.i - 1].end)
        if not hash_:
            return array
        result = {}
        if array:
            result["__array"] = array
        for key in order:
            result[key] = hash_[key]
        return result


def _lua_number(src):
    if src.lower().startswith('0x'):
        return int(src, 16)
    if re.match(r'^\d+$', src):
        return int(src)
    return float(src)


def parse_args(source, spans=None):
    """Parse a Lua argument list (the text between the outer parentheses).

    Pass a dict as `spans` to also receive "a:b" -> (start, stop) for every key it saw.
    """
    text = source
    parser = Parser(tokenize(text), text)
    args = []
    while parser.peek() is not None:
        if parser.at_op(','):
            parser.take()
            continue
        args.append(parser.parse_value())
    if spans is not None:
        spans.update(parser.spans)
    return args


# ---------------------------------------------------------------------------
# Lua rendering
# ---------------------------------------------------------------------------

def render_value(value):
    if isinstance(value, dict):
        if "__raw" in value and len(value) == 1:
            return value["__raw"]
        return render_table(value)
    if isinstance(value, list):
        return render_table(value)
    if isinstance(value, bool):
        return "true" if value else "false"
    if value is None:
        return "nil"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        out = repr(value)
        return out
    return render_string(str(value))


def render_string(value):
    out = ['"']
    for c in value:
        if c == '"':
            out.append('\\"')
        elif c == '\\':
            out.append('\\\\')
        elif c == '\n':
            out.append('\\n')
        elif c == '\r':
            out.append('\\r')
        elif c == '\t':
            out.append('\\t')
        elif ord(c) < 0x20:
            out.append('\\%d' % ord(c))
        else:
            out.append(c)
    out.append('"')
    return ''.join(out)


def render_key(key):
    if IDENT_RE.match(key) and key not in LUA_KEYWORDS:
        return key
    return "[%s]" % render_string(key)


def render_table(table, key_order=None):
    parts = []
    if isinstance(table, list):
        parts = [render_value(v) for v in table]
    else:
        for item in table.get("__array", []):
            parts.append(render_value(item))
        keys = [k for k in table.keys() if k != "__array"]
        if key_order:
            keys.sort(key=lambda k: (key_order.index(k) if k in key_order else len(key_order)))
        for key in keys:
            parts.append("%s = %s" % (render_key(key), render_value(table[key])))
    if not parts:
        return "{}"
    return "{ %s }" % ", ".join(parts)


# ---------------------------------------------------------------------------
# Entries
# ---------------------------------------------------------------------------

TAG_LETTERS = {"config": "k", "device": "d", "env": "e", "windowrule": "r",
               "layerrule": "r", "workspacerule": "r", "bind": "b", "unbind": "u",
               "global": "g"}
RULE_FN = {"windowrule": "hl.window_rule", "layerrule": "hl.layer_rule",
           "workspacerule": "hl.workspace_rule"}
FN_KIND = {"hl.window_rule": "windowrule", "hl.layer_rule": "layerrule",
           "hl.workspace_rule": "workspacerule", "hl.config": "config",
           "hl.device": "device", "hl.env": "env", "hl.bind": "bind", "hl.unbind": "unbind"}


def flatten_config(table, prefix=""):
    """hl.config({a = {b = 1, c = 2}}) -> [("a:b", 1), ("a:c", 2)]"""
    out = []
    if not isinstance(table, dict):
        return out
    for key, value in table.items():
        if key == "__array":
            continue
        path = "%s:%s" % (prefix, key) if prefix else key
        if isinstance(value, dict) and "__raw" not in value:
            out.extend(flatten_config(value, path))
        else:
            out.append((path, value))
    return out


def lua_parts(path):
    """The Lua table path for a hyprctl-style key. hyprctl still answers to the old dashed
    spellings (input:touchpad:tap-to-click); the Lua config API knows only the underscored
    ones, and an unknown table key is rejected on load, so every part is written that way."""
    return [part.replace("-", "_") for part in path.split(":")]


def nest_config(path, value):
    parts = lua_parts(path)
    node = value
    for part in reversed(parts):
        node = {part: node}
    return node


def render_entry(entry):
    """Return the Lua source line for an entry, without the tag or newline."""
    kind = entry.get("kind")
    if kind == "config":
        return "hl.config(%s)" % render_table(nest_config(entry["key"], entry.get("value")))
    if kind == "device":
        return "hl.device(%s)" % render_table(entry.get("spec") or {}, key_order=["name"])
    if kind == "env":
        return "hl.env(%s, %s)" % (render_string(entry["name"]), render_string(str(entry.get("value", ""))))
    if kind in RULE_FN:
        return "%s(%s)" % (RULE_FN[kind], render_table(entry.get("spec") or {}, key_order=["match"]))
    if kind == "global":
        name = entry.get("name", "")
        if not IDENT_RE.match(name) or name in LUA_KEYWORDS:
            raise ValueError("not a Lua global name: %r" % name)
        return "%s = %s" % (name, render_value(entry.get("value")))
    if kind == "unbind":
        return "pcall(hl.unbind, %s)" % render_string(entry["key"])
    if kind == "bind":
        parts = [render_string(entry["key"]), render_value(entry.get("dispatcher"))]
        opts = entry.get("opts")
        if opts:
            parts.append(render_table(opts))
        return "hl.bind(%s)" % ", ".join(parts)
    raise ValueError("unknown entry kind %r" % kind)


def entry_id(entry, index):
    given = entry.get("id")
    if given:
        return str(given).replace("\n", " ")
    kind = entry.get("kind")
    if kind == "config":
        return entry["key"]
    if kind in ("env", "global"):
        return entry["name"]
    if kind == "device":
        return (entry.get("spec") or {}).get("name", "device%d" % index)
    if kind in ("bind", "unbind"):
        return entry["key"]
    return "%s%d" % (TAG_LETTERS.get(kind, "x"), index)


def render_region(entries):
    """Render the whole managed region, fences included, as a list of lines."""
    rendered = []
    for index, entry in enumerate(entries):
        if entry.get("kind") == "raw":
            rendered.append((entry.get("text", "").rstrip("\n"), None))
            continue
        code = render_entry(entry)
        tag = "--@%s %s" % (TAG_LETTERS[entry["kind"]], entry_id(entry, index))
        rendered.append((code, tag))
    width = max([len(code) for code, tag in rendered if tag] or [0])
    width = min(width, ALIGN_COLUMN)
    lines = [BEGIN_LINE]
    for code, tag in rendered:
        if tag is None:
            lines.append(code + "\n")
        else:
            lines.append("%s%s%s\n" % (code, " " * max(2, width - len(code) + 2), tag))
    lines.append(END_LINE)
    return lines


# ---------------------------------------------------------------------------
# Scanning a file
# ---------------------------------------------------------------------------

CALL_RE = re.compile(r'(?m)^[ \t]*(pcall\(\s*(hl\.unbind)\s*,|(hl\.[a-z_]+)\s*\()')


def scan_calls(text):
    """Yield (fn, args_source, start, end, args_offset) for every top-level hl.* call."""
    out = []
    for m in CALL_RE.finditer(text):
        if m.group(2):                      # pcall(hl.unbind, "KEY")
            fn = m.group(2)
            open_paren = text.index('(', m.start(1))
        else:
            fn = m.group(3)
            open_paren = m.end(1) - 1
        close = _match_paren(text, open_paren)
        if close is None:
            continue
        args = text[open_paren + 1:close]
        if m.group(2):
            args = args.split(',', 1)[1] if ',' in args else args
        out.append((fn, args, m.start(), close + 1, open_paren + 1))
    return out


def _match_paren(text, i):
    depth = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c in '"\'':
            i = _skip_string(text, i)
            continue
        if c == '[':
            j = _skip_long_bracket(text, i)
            if j is not None:
                i = j
                continue
        if text.startswith('--', i):
            i = _skip_comment(text, i)
            continue
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return None


# Single-character operators that would make whatever follows a value part of the same
# expression rather than the start of the next statement.
CONTINUATION_OPS = set(".+-*/%^<>=~[(,")


def scan_assignments(text):
    """Top-level `name = <literal>` statements, the form hyprland/variables.lua uses.

    Only a bare name at the start of a line, assigned exactly one literal, counts. Anything
    indented, `local`, or built out of an expression is left alone on purpose: this exists so
    the default app chains can be read and rewritten, not to become a second Lua interpreter.
    """
    out = []
    tokens = tokenize(text)
    for index, tok in enumerate(tokens):
        if tok.kind != 'name' or tok.value in LUA_KEYWORDS:
            continue
        if tok.start != 0 and text[tok.start - 1] != '\n':
            continue
        eq = tokens[index + 1] if index + 1 < len(tokens) else None
        if eq is None or eq.kind != 'op' or eq.value != '=':
            continue
        value_tok = tokens[index + 2] if index + 2 < len(tokens) else None
        if value_tok is None:
            continue
        after = tokens[index + 3] if index + 3 < len(tokens) else None
        if after is not None:
            if after.kind == 'op' and after.value in CONTINUATION_OPS:
                continue
            # A statement that ends where the next one begins, on the same line, is something
            # this scanner does not understand well enough to touch.
            if '\n' not in text[value_tok.end:after.start]:
                continue
        if value_tok.kind == 'string':
            value = value_tok.value
        elif value_tok.kind == 'number':
            value = _lua_number(value_tok.value)
        elif value_tok.kind == 'name' and value_tok.value in ('true', 'false'):
            value = value_tok.value == 'true'
        else:
            continue
        out.append({"name": tok.value, "value": value, "start": tok.start, "end": value_tok.end})
    return out


def _unresolved(kind, value, line_number):
    """A call whose key is a variable rather than a literal: visible, but not editable."""
    source = value.get("__raw") if isinstance(value, dict) else repr(value)
    return {"kind": kind, "key": None, "keyRaw": source, "unresolved": True, "line": line_number}


_MISSING = object()


def resolve_config(table, key):
    """The value at a colon-separated key inside an hl.config table."""
    node = table
    for part in lua_parts(key):
        if not isinstance(node, dict) or part not in node:
            return _MISSING
        node = node[part]
    return node


def call_to_entries(fn, args_source, line_number, args_offset=None, locate=None, key_hint=None):
    """Turn one parsed hl.* call into zero or more entries.

    One `hl.config` call can set thirty keys across thirty lines. With `args_offset` and a
    `locate(offset) -> (line, file_offset)` callback, each key reports its own line and the
    exact span that sets it, which is what makes "remove that one line" possible.

    `key_hint` is for a line the hub wrote and tagged: the tag says where the key ends, which
    matters when the value is itself a table. A gradient is `{ colors = {...}, angle = 45 }`,
    and flattening that blindly turns one key into `...:colors` and `...:angle` - two keys that
    were never written, neither of which can be reset or edited by the name it was set under.
    """
    kind = FN_KIND.get(fn)
    if kind is None:
        return []
    spans = {}
    try:
        args = parse_args(args_source, spans)
    except (ValueError, IndexError):
        return []
    if not args:
        return []
    if kind == "config":
        table = args[0]
        if not isinstance(table, dict):
            return []
        if key_hint:
            value = resolve_config(table, key_hint)
            if value is not _MISSING:
                return [{"kind": "config", "key": key_hint, "value": value,
                         "line": line_number}]
        out = []
        for key, value in flatten_config(table):
            entry = {"kind": "config", "key": key, "value": value, "line": line_number}
            span = spans.get(key)
            if span is not None and args_offset is not None and locate is not None:
                head = locate(args_offset + span[0])
                tail = locate(args_offset + span[1])
                if head is not None and tail is not None:
                    entry["line"] = head[0]
                    entry["span"] = [head[1], tail[1]]
            out.append(entry)
        return out
    if kind == "device":
        spec = args[0]
        if not isinstance(spec, dict):
            return []
        return [{"kind": "device", "spec": spec, "line": line_number}]
    if kind == "env":
        if len(args) >= 2:
            if not isinstance(args[0], str):
                return [_unresolved("env", args[0], line_number)]
            name, value = args[0], args[1]
        else:
            if not isinstance(args[0], str) or "=" not in args[0]:
                return [_unresolved("env", args[0], line_number)]
            name, value = args[0].split("=", 1)
            name, value = name.strip(), value.strip()
        return [{"kind": "env", "name": name, "value": value, "line": line_number}]
    if kind in RULE_FN:
        spec = args[0]
        if not isinstance(spec, dict):
            return []
        return [{"kind": kind, "spec": spec, "line": line_number}]
    if kind == "unbind":
        if not isinstance(args[0], str):
            return [_unresolved("unbind", args[0], line_number)]
        return [{"kind": "unbind", "key": args[0], "line": line_number}]
    if kind == "bind":
        if not isinstance(args[0], str):
            return [_unresolved("bind", args[0], line_number)]
        entry = {"kind": "bind", "key": args[0],
                 "dispatcher": args[1] if len(args) > 1 else None, "line": line_number}
        if len(args) > 2 and isinstance(args[2], dict):
            entry["opts"] = args[2]
        return [entry]
    return []


def find_region(lines):
    """Return (begin_index, end_index, version) with end exclusive, or (None, None, None)."""
    begin = end = version = None
    for index, line in enumerate(lines):
        m = BEGIN_RE.match(line)
        if m and begin is None:
            begin = index
            version = int(m.group(1)) if m.group(1) else 0
            continue
        if begin is not None and END_RE.match(line):
            end = index + 1
            break
    if begin is None or end is None:
        return None, None, None
    return begin, end, version


def read_file(path):
    if not os.path.exists(path):
        return None
    with open(path, 'r', encoding='utf-8', errors='surrogateescape') as handle:
        return handle.readlines()


def parse_region(lines, begin, end):
    """Parse the tagged entries inside the fence, preserving anything unrecognised."""
    entries = []
    for offset in range(begin + 1, end - 1):
        line = lines[offset]
        code, comment = split_code_and_comment(line)
        m = re.match(r'--@([a-z])\s*(.*?)\s*$', comment.strip())
        parsed = []
        if m and code.strip():
            calls = scan_calls(code)
            if calls:
                fn, args, _, _, _ = calls[0]
                parsed = call_to_entries(fn, args, offset + 1,
                                         key_hint=m.group(2)
                                         if m.group(1) == TAG_LETTERS["config"] else None)
            elif m.group(1) == TAG_LETTERS["global"]:
                found = scan_assignments(code)
                if found:
                    parsed = [{"kind": "global", "name": found[0]["name"],
                               "value": found[0]["value"], "line": offset + 1}]
            # A tag letter this version does not know about, or one that disagrees with the
            # line it sits on, means a newer shell wrote it. Keep the line, do not reinterpret.
            if parsed and TAG_LETTERS.get(parsed[0].get("kind")) != m.group(1):
                parsed = []
        if parsed:
            entry = parsed[0]
            entry["id"] = m.group(2)
            entry["managed"] = True
            entries.append(entry)
        else:
            entries.append({"kind": "raw", "text": line.rstrip("\n"), "line": offset + 1,
                            "managed": True, "unrecognised": True})
    return entries


def scan_unmanaged(lines, begin, end):
    """Entries outside the fence: what the hub would be overriding."""
    kept = []
    offsets = []
    position = 0
    for index, line in enumerate(lines):
        if begin is not None and begin <= index < end:
            position += len(line)
            continue
        kept.append(line)
        offsets.append((position, index + 1))
        position += len(line)
    text = ''.join(kept)
    # Map an offset in the joined text back to a source line number.
    joined = []
    running = 0
    for line, (source_offset, source_line) in zip(kept, offsets):
        joined.append((running, running + len(line), source_line, source_offset))
        running += len(line)

    def locate(offset):
        """Offset in the fence-less text -> (line number, offset in the real file)."""
        for start, stop, source_line, source_offset in joined:
            if start <= offset < stop:
                return source_line, source_offset + (offset - start)
        if joined and offset == running:
            start, stop, source_line, source_offset = joined[-1]
            return source_line, source_offset + (stop - start)
        return None

    def line_at(offset):
        found = locate(offset)
        return found[0] if found else 0

    out = []
    for fn, args, start, _, args_offset in scan_calls(text):
        out.extend(call_to_entries(fn, args, line_at(start), args_offset, locate))
    for found in scan_assignments(text):
        entry = {"kind": "global", "name": found["name"], "value": found["value"],
                 "line": line_at(found["start"])}
        head = locate(found["start"])
        tail = locate(found["end"])
        if head is not None and tail is not None:
            entry["span"] = [head[1], tail[1]]
        out.append(entry)
    for entry in out:
        entry["managed"] = False
    return out


# ---------------------------------------------------------------------------
# Writing
# ---------------------------------------------------------------------------

def guard_path(path, custom_dir):
    resolved = os.path.realpath(os.path.expanduser(path))
    root = os.path.realpath(os.path.expanduser(custom_dir))
    if resolved != root and not resolved.startswith(root + os.sep):
        raise SystemExit("refusing to write outside %s: %s" % (root, resolved))
    return resolved


def compose(lines, region_lines):
    """Put the region back, in place if it was already there, otherwise at the end."""
    begin, end, _ = find_region(lines)
    if begin is not None:
        return lines[:begin] + region_lines + lines[end:]
    body = list(lines)
    while body and not body[-1].strip():
        body.pop()
    if body and not body[-1].endswith("\n"):
        body[-1] += "\n"
    if body:
        body.append("\n")
    return body + region_lines


def backup(path):
    os.makedirs(BACKUP_DIR, exist_ok=True)
    name = os.path.basename(path)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    target = os.path.join(BACKUP_DIR, "%s.%s.bak" % (name, stamp))
    suffix = 0
    while os.path.exists(target):
        suffix += 1
        target = os.path.join(BACKUP_DIR, "%s.%s-%d.bak" % (name, stamp, suffix))
    with open(path, 'rb') as src, open(target, 'wb') as dst:
        dst.write(src.read())
    old = sorted(f for f in os.listdir(BACKUP_DIR) if f.startswith(name + "."))
    for stale in old[:-BACKUP_KEEP]:
        try:
            os.remove(os.path.join(BACKUP_DIR, stale))
        except OSError:
            pass
    return target


def latest_backup(path):
    """Newest backup of `path`, so the page can say how old the safety net is."""
    name = os.path.basename(path)
    try:
        names = [f for f in os.listdir(BACKUP_DIR)
                 if f.startswith(name + ".") and f.endswith(".bak")]
    except OSError:
        return None
    newest = None
    for candidate in names:
        full = os.path.join(BACKUP_DIR, candidate)
        try:
            stamp = os.stat(full).st_mtime
        except OSError:
            continue
        if newest is None or stamp > newest[1]:
            newest = (full, stamp)
    if newest is None:
        return None
    return {"path": newest[0], "mtime": int(newest[1]), "count": len(names)}


def write_atomic(path, lines):
    import tempfile
    directory = os.path.dirname(os.path.abspath(path))
    os.makedirs(directory, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', errors='surrogateescape',
                                     dir=directory, delete=False) as tmp:
        tmp.writelines(lines)
        tmp_name = tmp.name
    if os.path.exists(path):
        os.chmod(tmp_name, os.stat(path).st_mode)
    else:
        os.chmod(tmp_name, 0o644)
    os.replace(tmp_name, path)


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def read_one(path, want_unmanaged=True):
    """Everything the GUI knows about one file. Split out of cmd_read so a whole
    round of reads can be answered by a single interpreter start."""
    path = os.path.realpath(os.path.expanduser(path))
    lines = read_file(path)
    result = {"version": REGION_VERSION, "file": path, "exists": lines is not None,
              "hasRegion": False, "regionVersion": None, "entries": [], "unmanaged": []}
    if lines is None:
        return result
    begin, end, version = find_region(lines)
    if begin is not None:
        result["hasRegion"] = True
        result["regionVersion"] = version
        result["regionStart"] = begin + 1
        result["regionEnd"] = end
        result["entries"] = parse_region(lines, begin, end)
        result["regionText"] = "".join(lines[begin:end])
    if want_unmanaged:
        result["unmanaged"] = scan_unmanaged(lines, begin, end)
    result["backup"] = latest_backup(path)
    return result


def cmd_read(args):
    """One --file prints that file's result; several print {"files": [...]} in the
    order asked. Python takes ~13 ms to start and ~25 ms to do the work, so reading
    the five custom files one process at a time spent more time starting up than
    reading."""
    want = not args.no_unmanaged
    results = [read_one(path, want) for path in args.file]
    print(json.dumps(results[0] if len(results) == 1 else {"files": results}))
    return 0


def cmd_write(args):
    path = guard_path(args.file, args.custom_dir)
    raw = sys.stdin.read() if args.json == '-' else open(os.path.expanduser(args.json)).read()
    try:
        document = json.loads(raw)
    except ValueError as error:
        print(json.dumps({"ok": False, "error": "invalid JSON: %s" % error}))
        return 1
    entries = document.get("entries", [])
    lines = read_file(path)
    existed = lines is not None
    lines = lines or []
    try:
        region = render_region(entries) if entries else []
    except (ValueError, KeyError) as error:
        print(json.dumps({"ok": False, "error": "cannot render: %s" % error}))
        return 1
    if entries:
        new_lines = compose(lines, region)
    else:
        begin, end, _ = find_region(lines)
        new_lines = lines[:begin] + lines[end:] if begin is not None else lines

    if new_lines == lines and existed:
        print(json.dumps({"ok": True, "changed": False, "file": path}))
        return 0
    if args.dry_run:
        import difflib
        diff = ''.join(difflib.unified_diff(lines, new_lines,
                                            fromfile=path + " (current)",
                                            tofile=path + " (proposed)"))
        print(json.dumps({"ok": True, "changed": True, "file": path, "diff": diff,
                          "created": not existed}))
        return 0
    saved = backup(path) if existed else None
    write_atomic(path, new_lines)
    # The file exactly as `read` would describe it, so the caller can update its own copy
    # instead of reading it back. Re-reading opened a window in which the file on disk and
    # the caller's idea of it disagreed, and edits made in that window were built on the
    # older one; it also meant the reload this write causes had to be answered with a read
    # of every file, for a change this side already knows in full.
    print(json.dumps({"ok": True, "changed": True, "file": path, "backup": saved,
                      "created": not existed, "record": read_one(path)}))
    return 0


def cmd_strip(args):
    path = guard_path(args.file, args.custom_dir)
    lines = read_file(path)
    if lines is None:
        print(json.dumps({"ok": True, "changed": False, "file": path}))
        return 0
    begin, end, _ = find_region(lines)
    if begin is None:
        print(json.dumps({"ok": True, "changed": False, "file": path}))
        return 0
    new_lines = lines[:begin] + lines[end:]
    while new_lines and not new_lines[-1].strip():
        new_lines.pop()
    if args.dry_run:
        import difflib
        diff = ''.join(difflib.unified_diff(lines, new_lines, fromfile=path, tofile=path))
        print(json.dumps({"ok": True, "changed": True, "file": path, "diff": diff}))
        return 0
    saved = backup(path)
    write_atomic(path, new_lines)
    print(json.dumps({"ok": True, "changed": True, "file": path, "backup": saved}))
    return 0


def _config_keys(entries):
    """The (key, value) pairs a scan found, for comparing a file against itself."""
    out = []
    for entry in entries:
        if entry.get("kind") != "config" or not entry.get("key"):
            continue
        value = entry.get("value")
        # Taking the last key out of a table leaves an empty one behind. It sets nothing,
        # so it must not read as a changed setting.
        if isinstance(value, (list, dict)) and len(value) == 0:
            continue
        out.append((entry["key"], json.dumps(value, sort_keys=True)))
    return sorted(out)


def _syntax_ok(lines):
    """Ask a real Lua parser, when there is one. Absence is not a failure."""
    import shutil
    import subprocess
    import tempfile
    luac = shutil.which("luac") or shutil.which("luac5.4")
    if luac is None:
        return True
    handle, temp = tempfile.mkstemp(suffix=".lua")
    try:
        with os.fdopen(handle, "w", encoding="utf-8", errors="surrogateescape") as out:
            out.writelines(lines)
        return subprocess.call([luac, "-p", temp],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) == 0
    finally:
        os.unlink(temp)


def cmd_drop(args):
    """Delete the one hand-written assignment outside the fence that sets --key.

    Only ever removes what it can prove it is removing: the span comes from the same parse
    the UI showed, the result is re-scanned, and every other setting in the file has to come
    back identical or nothing is written.
    """
    path = guard_path(args.file, args.custom_dir)
    lines = read_file(path)
    if lines is None:
        print(json.dumps({"ok": False, "error": "no such file: %s" % path}))
        return 1
    begin, end, _ = find_region(lines)
    before = scan_unmanaged(lines, begin, end)
    hits = [entry for entry in before
            if entry.get("kind") == "config" and entry.get("key") == args.key and entry.get("span")]
    if not hits:
        print(json.dumps({"ok": False,
                          "error": "%s is not set by hand in this file" % args.key}))
        return 1
    # Lua applies the last one, so that is the one worth removing.
    target = hits[-1]
    text = "".join(lines)
    start, stop = target["span"]
    leaf = args.key.split(":")[-1]
    if leaf not in text[start:stop]:
        print(json.dumps({"ok": False, "error": "the file changed since it was read"}))
        return 1

    cut = stop
    while cut < len(text) and text[cut] in " \t":
        cut += 1
    if cut < len(text) and text[cut] in ",;":
        cut += 1
        while cut < len(text) and text[cut] in " \t":
            cut += 1
    line_start = text.rfind("\n", 0, start) + 1
    line_end = text.find("\n", cut)
    line_end = len(text) if line_end < 0 else line_end + 1
    if text[line_start:start].strip() == "" and text[cut:line_end].strip() == "":
        updated = text[:line_start] + text[line_end:]   # the line held nothing else
    else:
        updated = text[:start] + text[cut:]             # several keys share the line
    new_lines = updated.splitlines(keepends=True)

    new_begin, new_end, _ = find_region(new_lines)
    after = scan_unmanaged(new_lines, new_begin, new_end)
    expected = [entry for entry in before if entry is not target]
    problem = None
    if _config_keys(after) != _config_keys(expected):
        problem = "removing that line would change other settings too"
    elif ((lines[begin:end] if begin is not None else [])
          != (new_lines[new_begin:new_end] if new_begin is not None else [])):
        problem = "the managed block would move"
    elif not _syntax_ok(new_lines):
        problem = "the result is not valid Lua"
    if problem:
        print(json.dumps({"ok": False, "error": problem}))
        return 1

    import difflib
    diff = ''.join(difflib.unified_diff(lines, new_lines,
                                        fromfile=path + " (current)",
                                        tofile=path + " (proposed)"))
    if args.dry_run:
        print(json.dumps({"ok": True, "changed": True, "file": path, "diff": diff,
                          "line": target.get("line")}))
        return 0
    saved = backup(path)
    write_atomic(path, new_lines)
    print(json.dumps({"ok": True, "changed": True, "file": path, "backup": saved,
                      "line": target.get("line"), "diff": diff}))
    return 0


class Args(object):
    """What the commands were handed when this parsed with argparse."""

    def __init__(self, values):
        self.__dict__.update(values)


# command -> (handler, {flag: (attribute, kind, default)}, [attributes that must be given]).
# `kind` is "value" for one argument, "append" for one that may repeat, "flag" for none.
def _specs():
    common = {"--file": ("file", "value", None),
              "--dry-run": ("dry_run", "flag", False),
              "--custom-dir": ("custom_dir", "value", DEFAULT_CUSTOM_DIR)}
    write = dict(common)
    write["--json"] = ("json", "value", "-")
    drop = dict(common)
    drop["--key"] = ("key", "value", None)
    return {
        "read": (cmd_read, {"--file": ("file", "append", None),
                            "--no-unmanaged": ("no_unmanaged", "flag", False)}, ["file"]),
        "write": (cmd_write, write, ["file"]),
        "strip": (cmd_strip, common, ["file"]),
        "drop-key": (cmd_drop, drop, ["file", "key"]),
    }


def _fail(message):
    sys.stderr.write("hyprgui: %s\n" % message)
    return 2


def main():
    argv = sys.argv[1:]
    specs = _specs()
    if not argv or argv[0] not in specs:
        return _fail("expected one of %s" % ", ".join(sorted(specs)))
    handler, options, required = specs[argv[0]]

    values = {}
    for name, kind, default in options.values():
        values[name] = [] if kind == "append" else default

    index = 1
    while index < len(argv):
        token = argv[index]
        index += 1
        argument = None
        if "=" in token and token.startswith("--"):
            token, argument = token.split("=", 1)
        if token not in options:
            return _fail("%s does not take %s" % (argv[0], token))
        name, kind, _ = options[token]
        if kind == "flag":
            if argument is not None:
                return _fail("%s takes no value" % token)
            values[name] = True
            continue
        if argument is None:
            if index >= len(argv):
                return _fail("%s needs a value" % token)
            argument = argv[index]
            index += 1
        if kind == "append":
            values[name].append(argument)
        else:
            values[name] = argument

    for name in required:
        if not values.get(name):
            return _fail("%s needs --%s" % (argv[0], name.replace("_", "-")))
    return handler(Args(values))


if __name__ == "__main__":
    sys.exit(main())
