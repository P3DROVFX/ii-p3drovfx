#!/usr/bin/env python3
"""Manage Matugen templates in the user's config.toml without touching the rest.

The file is hand-edited by users and other installers, so it is never
re-serialised: every change rewrites only the lines of one `[templates.<name>]`
block, the result is parsed with tomllib before it replaces the file, and the
previous version is kept as `config.toml.bak-ii`.

A disabled template stays in the file as a commented block (`#~ ` prefix), so
Matugen skips it and enabling it restores the exact lines.

Every command prints one JSON object: `{"ok": true, ...}` or
`{"ok": false, "error": "...", "code": "..."}` (exit status 0 / 1).

    list                       templates + theme catalog
    add NAME --input P --output P [--post-hook C] [--pre-hook C] [--create]
    update NAME [--rename N] [--input P] [--output P] [--post-hook C] [--pre-hook C]
    remove NAME [--delete-input]
    enable NAME | disable NAME
    test NAME [--mode dark|light] [--color HEX]
    install-theme ID | uninstall-theme ID
    pick-file [--save]

`MATUGEN_CONFIG_DIR` overrides `~/.config/matugen` (tests), `MATUGEN_BIN`
overrides the Matugen launcher.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
CATALOG_DIR = SCRIPT_DIR / "matugen-themes"
DISABLED_PREFIX = "#~ "
NAME_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
BARE_KEY_RE = re.compile(r"^[A-Za-z0-9_-]+$")
MANAGED_KEYS = ("input_path", "output_path", "pre_hook", "post_hook")
# The shell paints itself from this one; without it nothing follows the wallpaper.
LOCKED = {"m3colors"}
# Shipped by ii: editable, but the UI warns before removing them.
CORE = {
    "m3colors", "hyprland", "hyprlock", "fuzzel", "gtk3", "gtk4", "kde_colors",
    "wallpaper", "vscode", "vesktop", "kvantum_svg", "kvantum_kvconfig",
}


class ManagerError(Exception):
    def __init__(self, message: str, code: str = "error"):
        super().__init__(message)
        self.code = code


# ── Paths ──────────────────────────────────────────────────────────────────


def config_dir() -> Path:
    override = os.environ.get("MATUGEN_CONFIG_DIR")
    if override:
        return Path(override)
    base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(base) / "matugen"


def config_path() -> Path:
    return config_dir() / "config.toml"


def expand(path: str) -> Path:
    """Matugen expands `~`; environment variables are expanded for the checks too."""
    return Path(os.path.expandvars(os.path.expanduser(path)))


def contract(path: Path | str) -> str:
    text = str(path)
    home = str(Path.home())
    if text == home or text.startswith(home + os.sep):
        return "~" + text[len(home):]
    return text


# ── TOML text helpers ──────────────────────────────────────────────────────


def toml_string(value: str) -> str:
    if "'" not in value and not any(ord(c) < 32 or c == "\x7f" for c in value):
        return f"'{value}'"
    out = []
    for c in value:
        if c == "\\":
            out.append("\\\\")
        elif c == '"':
            out.append('\\"')
        elif c == "\n":
            out.append("\\n")
        elif c == "\t":
            out.append("\\t")
        elif c == "\r":
            out.append("\\r")
        elif ord(c) < 32 or c == "\x7f":
            out.append(f"\\u{ord(c):04x}")
        else:
            out.append(c)
    return '"' + "".join(out) + '"'


def toml_key(name: str) -> str:
    # JSON escapes are valid TOML basic-string escapes.
    return name if BARE_KEY_RE.match(name) else json.dumps(name)


def split_dotted(key: str) -> list[str] | None:
    """`templates."a b".x` → ["templates", "a b", "x"]; None when malformed."""
    parts, i, n = [], 0, len(key)
    while i < n:
        while i < n and key[i] in " \t":
            i += 1
        if i >= n:
            return None
        if key[i] in "\"'":
            quote = key[i]
            j = i + 1
            buf = []
            while j < n and key[j] != quote:
                if quote == '"' and key[j] == "\\" and j + 1 < n:
                    try:
                        buf.append(tomllib.loads(f'k = "{key[j:j + 2]}"')["k"])
                    except tomllib.TOMLDecodeError:
                        return None
                    j += 2
                    continue
                buf.append(key[j])
                j += 1
            if j >= n:
                return None
            parts.append("".join(buf))
            i = j + 1
        else:
            m = re.match(r"[A-Za-z0-9_-]+", key[i:])
            if not m:
                return None
            parts.append(m.group(0))
            i += m.end()
        while i < n and key[i] in " \t":
            i += 1
        if i < n:
            if key[i] != ".":
                return None
            i += 1
    return parts or None


HEADER_RE = re.compile(r"^\s*(\[\[?)\s*(.+?)\s*(\]\]?)\s*(#.*)?$")


def parse_header(line: str) -> list[str] | None:
    m = HEADER_RE.match(line)
    if not m or len(m.group(1)) != len(m.group(3)):
        return None
    return split_dotted(m.group(2))


# ── Document model ─────────────────────────────────────────────────────────


@dataclass
class Block:
    name: str
    start: int  # header line
    end: int  # one past the last line that belongs to the block
    disabled: bool
    values: dict = field(default_factory=dict)
    editable: bool = True


class Document:
    def __init__(self, text: str):
        self.lines = text.splitlines()
        self.trailing_newline = text.endswith("\n") or text == ""

    @classmethod
    def load(cls) -> "Document":
        path = config_path()
        if not path.exists():
            return cls("")
        return cls(path.read_text(encoding="utf-8"))

    def text(self) -> str:
        body = "\n".join(self.lines)
        return body + "\n" if self.lines else ""

    # Headers of the live (uncommented) and disabled blocks, in file order.
    def _headers(self) -> list[tuple[int, list[str], bool]]:
        found = []
        for i, line in enumerate(self.lines):
            if line.startswith(DISABLED_PREFIX):
                key = parse_header(line[len(DISABLED_PREFIX):])
                if key:
                    found.append((i, key, True))
                continue
            key = parse_header(line)
            if key:
                found.append((i, key, False))
        return found

    def blocks(self) -> list[Block]:
        headers = self._headers()
        result = []
        for idx, (line_no, key, disabled) in enumerate(headers):
            if len(key) != 2 or key[0] != "templates":
                continue
            name = key[1]
            # The block runs until a header outside `templates.<name>.*`.
            end = len(self.lines)
            for nxt_line, nxt_key, nxt_disabled in headers[idx + 1:]:
                if nxt_key[:2] == ["templates", name] and len(nxt_key) > 2 and nxt_disabled == disabled:
                    continue
                end = nxt_line
                break
            if disabled:
                # A disabled block is only its run of prefixed lines.
                stop = line_no + 1
                while stop < end and self.lines[stop].startswith(DISABLED_PREFIX):
                    stop += 1
                end = stop
            # Comments and blank lines before the next header belong to it.
            while end > line_no + 1 and self._is_trivia(self.lines[end - 1], disabled):
                end -= 1
            block = Block(name=name, start=line_no, end=end, disabled=disabled)
            raw = self.block_lines(block)
            try:
                parsed = tomllib.loads("\n".join(raw))
                block.values = parsed.get("templates", {}).get(name, {})
            except tomllib.TOMLDecodeError:
                block.values = {}
                block.editable = False
            block.editable = block.editable and self._single_line_values(raw)
            result.append(block)
        return result

    @staticmethod
    def _is_trivia(line: str, disabled: bool) -> bool:
        if disabled:
            return False
        stripped = line.strip()
        return stripped == "" or stripped.startswith("#")

    @staticmethod
    def _single_line_values(raw: list[str]) -> bool:
        """Managed keys must each sit on one line for in-place edits."""
        for line in raw[1:]:
            m = re.match(r"^\s*([A-Za-z0-9_-]+)\s*=", line)
            if m and m.group(1) in MANAGED_KEYS:
                try:
                    tomllib.loads(line.strip())
                except tomllib.TOMLDecodeError:
                    return False
        return True

    def block_lines(self, block: Block) -> list[str]:
        raw = self.lines[block.start:block.end]
        if block.disabled:
            raw = [line[len(DISABLED_PREFIX):] if line.startswith(DISABLED_PREFIX) else line for line in raw]
        return raw

    def find(self, name: str) -> Block | None:
        for block in self.blocks():
            if block.name == name:
                return block
        return None

    def parsed(self) -> dict:
        return tomllib.loads(self.text())


def render_block(name: str, values: dict) -> list[str]:
    lines = [f"[templates.{toml_key(name)}]"]
    for key in MANAGED_KEYS:
        if values.get(key):
            lines.append(f"{key} = {toml_string(values[key])}")
    return lines


def set_key(lines: list[str], key: str, value: str | None) -> list[str]:
    """Replace, add or drop `key = …` in a block's (uncommented) lines."""
    pattern = re.compile(rf"^\s*{re.escape(key)}\s*=")
    out = []
    replaced = False
    for line in lines:
        if pattern.match(line):
            if value and not replaced:
                indent = line[: len(line) - len(line.lstrip())]
                out.append(f"{indent}{key} = {toml_string(value)}")
            replaced = True
            continue
        out.append(line)
    if value and not replaced:
        # After the last key of the template's own table, before any subtable.
        insert_at = 1
        for i, line in enumerate(out[1:], start=1):
            if parse_header(line):
                break
            if line.strip() and not line.strip().startswith("#"):
                insert_at = i + 1
        out.insert(insert_at, f"{key} = {toml_string(value)}")
    return out


# ── Persisting ─────────────────────────────────────────────────────────────


def save(doc: Document, original: str | None) -> None:
    text = doc.text()
    try:
        tomllib.loads(text)
    except tomllib.TOMLDecodeError as exc:  # never write a file Matugen can't read
        raise ManagerError(f"the change would leave config.toml invalid: {exc}", "invalid_result") from exc
    path = config_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    if original is not None and original != text:
        (path.parent / "config.toml.bak-ii").write_text(original, encoding="utf-8")
    # Follow a symlinked config (dotfile managers) instead of replacing the link.
    target = path.resolve() if path.is_symlink() else path
    fd, tmp = tempfile.mkstemp(prefix=".config.toml.", dir=target.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
        if target.exists():
            shutil.copymode(target, tmp)
        os.replace(tmp, target)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


def load_with_original() -> tuple[Document, str | None]:
    path = config_path()
    if not path.exists():
        return Document("[config]\nversion_check = false\n"), None
    original = path.read_text(encoding="utf-8")
    doc = Document(original)
    try:
        doc.parsed()
    except tomllib.TOMLDecodeError as exc:
        raise ManagerError(f"config.toml is not valid TOML, fix it first: {exc}", "invalid_config") from exc
    return doc, original


# ── Listing ────────────────────────────────────────────────────────────────


def template_entry(block: Block | None, name: str, values: dict, source: str) -> dict:
    input_path = values.get("input_path", "")
    output_path = values.get("output_path", "")
    input_ok = bool(input_path) and expand(input_path).is_file()
    output_ok = bool(output_path) and expand(output_path).exists()
    extra = sorted(k for k in values if k not in MANAGED_KEYS)
    return {
        "name": name,
        "input": input_path,
        "output": output_path,
        "postHook": values.get("post_hook", "") if isinstance(values.get("post_hook"), str) else "",
        "preHook": values.get("pre_hook", "") if isinstance(values.get("pre_hook"), str) else "",
        "enabled": not (block and block.disabled),
        "editable": bool(block and block.editable) and name not in LOCKED,
        "locked": name in LOCKED,
        "core": name in CORE,
        "source": source,
        "extraKeys": extra,
        "inputExists": input_ok,
        "outputExists": output_ok,
        "managedFile": bool(input_path) and is_managed_file(expand(input_path)),
        "fromCatalog": bool(input_path) and is_managed_file(expand(input_path), "ii-themes"),
        "theme": theme_for(name, output_path),
    }


def list_templates(doc: Document) -> list[dict]:
    entries = []
    seen = set()
    for block in doc.blocks():
        if block.name in seen:
            continue
        seen.add(block.name)
        entries.append(template_entry(block, block.name, block.values, "block"))
    # Templates written as dotted keys / inline tables: shown, not editable here.
    try:
        live = doc.parsed().get("templates", {})
    except tomllib.TOMLDecodeError:
        live = {}
    for name, values in live.items():
        if name not in seen and isinstance(values, dict):
            entries.append(template_entry(None, name, values, "inline"))
    return entries


def is_managed_file(path: Path, sub: str = "") -> bool:
    try:
        path.resolve().relative_to((config_dir() / "templates" / sub).resolve())
        return True
    except ValueError:
        return False


# ── Theme catalog ──────────────────────────────────────────────────────────


def load_catalog() -> list[dict]:
    path = CATALOG_DIR / "catalog.json"
    if not path.exists():
        return []
    return json.loads(path.read_text(encoding="utf-8")).get("themes", [])


def theme_for(name: str, output: str) -> str:
    for theme in load_catalog():
        if theme["id"] == name or (output and expand(output) == expand(theme["output"])):
            return theme["id"]
    return ""


def catalog_entries(templates: list[dict]) -> list[dict]:
    result = []
    for theme in load_catalog():
        match = next((t for t in templates if t["theme"] == theme["id"]), None)
        result.append({
            **{k: theme.get(k, "") for k in ("id", "name", "symbol", "description", "output", "postHook", "setup")},
            "app": theme.get("app", ""),
            "installed": match is not None,
            "templateName": match["name"] if match else "",
            "fromCatalog": bool(match and match["fromCatalog"]),
            "enabled": bool(match and match["enabled"]),
            "appFound": app_found(theme),
        })
    return result


def app_found(theme: dict) -> bool:
    binary = theme.get("app", "")
    return bool(binary) and shutil.which(binary) is not None


# ── Commands ───────────────────────────────────────────────────────────────


def validate_name(name: str) -> None:
    if not NAME_RE.match(name or ""):
        raise ManagerError("names use letters, digits, - and _ (up to 64)", "invalid_name")


def validate_paths(input_path: str, output_path: str) -> None:
    if not input_path.strip():
        raise ManagerError("the template file is required", "missing_input")
    if not output_path.strip():
        raise ManagerError("the output path is required", "missing_output")
    if expand(input_path).resolve() == expand(output_path).resolve():
        raise ManagerError("the output would overwrite the template itself", "same_path")
    if expand(output_path).is_dir():
        raise ManagerError("the output path is a folder; name the file to write", "output_is_dir")
    if expand(input_path).is_dir():
        raise ManagerError("the template path is a folder; pick a file", "input_is_dir")


# Matugen parses tags even inside comments, so the help text names them
# without the braces.
STARTER = """\
{comment} Matugen template for {name}. Rendered to {output}
{comment} each time the wallpaper or palette changes.
{comment}
{comment} Wrap a variable in double braces to insert it:
{comment}   colors.<role>.default.hex   (also .hex_stripped, .rgb, .rgba)
{comment}   roles: primary, on_primary, primary_container, secondary, tertiary,
{comment}          surface, surface_container, on_surface, outline, error, ...
{comment}   .light / .dark instead of .default pin a mode; mode and image too.

background = "{{{{colors.surface.default.hex}}}}"
foreground = "{{{{colors.on_surface.default.hex}}}}"
accent = "{{{{colors.primary.default.hex}}}}"
"""


def comment_for(path: str) -> str:
    suffix = Path(path).suffix.lower()
    if suffix in {".css", ".scss", ".rasi", ".js", ".ts", ".qml", ".json", ".jsonc", ".kdl"}:
        return "//"
    if suffix in {".lua", ".sql", ".hs"}:
        return "--"
    if suffix in {".vim"}:
        return '"'
    return "#"


def create_starter(name: str, input_path: str, output_path: str) -> None:
    path = expand(input_path)
    if path.exists():
        raise ManagerError("a file already exists at that template path", "input_exists")
    path.parent.mkdir(parents=True, exist_ok=True)
    comment = comment_for(output_path)
    text = STARTER.format(comment=comment, name=name, output=output_path)
    if comment == "//" and Path(output_path).suffix.lower() == ".json":
        # JSON has no comments: start from a plain object instead.
        text = ('{\n  "background": "{{colors.surface.default.hex}}",\n'
                '  "foreground": "{{colors.on_surface.default.hex}}",\n'
                '  "accent": "{{colors.primary.default.hex}}"\n}\n')
    elif comment == "//" and Path(output_path).suffix.lower() in {".css", ".scss", ".rasi"}:
        text = ("/* Matugen template for " + name + ". Wrap colors.<role>.default.hex in double braces. */\n"
                ":root {\n  --background: {{colors.surface.default.hex}};\n"
                "  --foreground: {{colors.on_surface.default.hex}};\n"
                "  --accent: {{colors.primary.default.hex}};\n}\n")
    path.write_text(text, encoding="utf-8")


def cmd_add(args) -> dict:
    validate_name(args.name)
    validate_paths(args.input, args.output)
    doc, original = load_with_original()
    if doc.find(args.name) or args.name in doc.parsed().get("templates", {}):
        raise ManagerError(f"a template named '{args.name}' already exists", "exists")
    created = False
    if args.create:
        create_starter(args.name, args.input, args.output)
        created = True
    elif not expand(args.input).is_file():
        raise ManagerError("the template file does not exist", "input_missing")
    lines = render_block(args.name, {
        "input_path": args.input, "output_path": args.output,
        "pre_hook": args.pre_hook, "post_hook": args.post_hook,
    })
    while doc.lines and not doc.lines[-1].strip():
        doc.lines.pop()
    if doc.lines:
        doc.lines.append("")
    doc.lines.extend(lines)
    try:
        save(doc, original)
    except BaseException:
        if created:
            expand(args.input).unlink(missing_ok=True)
        raise
    return {"name": args.name, "created": created}


def editable_block(doc: Document, name: str) -> Block:
    block = doc.find(name)
    if block is None:
        if name in doc.parsed().get("templates", {}):
            raise ManagerError("this template is written in a form that can only be edited in config.toml", "not_editable")
        raise ManagerError(f"no template named '{name}'", "not_found")
    if name in LOCKED:
        raise ManagerError("the shell's own palette template can't be changed here", "locked")
    if not block.editable:
        raise ManagerError("this template uses multi-line values; edit it in config.toml", "not_editable")
    return block


def replace_block(doc: Document, block: Block, raw: list[str]) -> None:
    if block.disabled:
        raw = [DISABLED_PREFIX + line for line in raw]
    doc.lines[block.start:block.end] = raw


def cmd_update(args) -> dict:
    doc, original = load_with_original()
    block = editable_block(doc, args.name)
    raw = doc.block_lines(block)
    values = dict(block.values)
    new_name = args.rename or args.name
    if args.rename and args.rename != args.name:
        validate_name(args.rename)
        if doc.find(args.rename) or args.rename in doc.parsed().get("templates", {}):
            raise ManagerError(f"a template named '{args.rename}' already exists", "exists")
        for i, line in enumerate(raw):
            key = parse_header(line)
            if key and key[:2] == ["templates", args.name]:
                head = HEADER_RE.match(line)
                rest = "".join(f".{toml_key(p)}" for p in key[2:])
                comment = f" {head.group(4)}" if head.group(4) else ""
                raw[i] = f"{head.group(1)}templates.{toml_key(args.rename)}{rest}{head.group(3)}{comment}"
    for key, value in (("input_path", args.input), ("output_path", args.output),
                       ("pre_hook", args.pre_hook), ("post_hook", args.post_hook)):
        if value is None:
            continue
        raw = set_key(raw, key, value)
        values[key] = value
    validate_paths(values.get("input_path", ""), values.get("output_path", ""))
    if not expand(values["input_path"]).is_file():
        raise ManagerError("the template file does not exist", "input_missing")
    replace_block(doc, block, raw)
    save(doc, original)
    return {"name": new_name}


def cmd_remove(args, drop_comment: str = "") -> dict:
    doc, original = load_with_original()
    block = editable_block(doc, args.name)
    input_path = block.values.get("input_path", "")
    if drop_comment and block.start > 0 and doc.lines[block.start - 1] == drop_comment:
        block.start -= 1
    end = block.end
    # Drop one separating blank line so removals don't pile up gaps.
    if end < len(doc.lines) and not doc.lines[end].strip() and (block.start == 0 or not doc.lines[block.start - 1].strip()):
        end += 1
    del doc.lines[block.start:end]
    while doc.lines and not doc.lines[-1].strip():
        doc.lines.pop()
    save(doc, original)
    deleted = False
    if args.delete_input and input_path:
        path = expand(input_path)
        # Only files the manager owns: never a template shared by another entry.
        still_used = any(expand(t["input"]) == path for t in list_templates(doc) if t["input"])
        if path.is_file() and is_managed_file(path) and not still_used:
            path.unlink()
            deleted = True
            try:
                path.parent.rmdir()  # its own folder, when empty
            except OSError:
                pass
    return {"name": args.name, "deletedInput": deleted}


def cmd_toggle(name: str, enable: bool) -> dict:
    doc, original = load_with_original()
    block = editable_block(doc, name)
    if block.disabled != enable:
        return {"name": name, "enabled": enable, "changed": False}
    if enable:
        values = block.values
        if values.get("input_path") and not expand(values["input_path"]).is_file():
            raise ManagerError("the template file is missing; Matugen would abort on every wallpaper change", "input_missing")
        doc.lines[block.start:block.end] = doc.block_lines(block)
    else:
        doc.lines[block.start:block.end] = [DISABLED_PREFIX + line for line in doc.lines[block.start:block.end]]
    save(doc, original)
    return {"name": name, "enabled": enable, "changed": True}


# ── Test render ────────────────────────────────────────────────────────────

ANSI_RE = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


def matugen_command() -> list[str]:
    override = os.environ.get("MATUGEN_BIN")
    if override:
        return [override]
    launcher = SCRIPT_DIR / "matugen.sh"
    if launcher.exists():
        return ["bash", str(launcher)]
    return ["matugen"]


def current_palette() -> tuple[str, str]:
    """Primary colour and mode of the palette the shell is showing."""
    state = os.environ.get("XDG_STATE_HOME") or str(Path.home() / ".local/state")
    colors = Path(state) / "quickshell/user/generated/colors.json"
    try:
        data = json.loads(colors.read_text(encoding="utf-8"))
        primary = data.get("source_color") or data.get("primary") or "#6750A4"
        background = data.get("background", "#141218").lstrip("#")
        luma = sum(int(background[i:i + 2], 16) * w for i, w in ((0, 0.299), (2, 0.587), (4, 0.114)))
        return primary, "light" if luma > 128 else "dark"
    except (OSError, ValueError, json.JSONDecodeError):
        return "#6750A4", "dark"


def cmd_test(args) -> dict:
    doc = Document.load()
    templates = {t["name"]: t for t in list_templates(doc)}
    entry = templates.get(args.name)
    if entry is None:
        raise ManagerError(f"no template named '{args.name}'", "not_found")
    if not entry["inputExists"]:
        raise ManagerError("the template file does not exist", "input_missing")
    color, mode = current_palette()
    color = args.color or color
    mode = args.mode or mode
    try:
        custom = doc.parsed().get("config", {}).get("custom_colors", {})
    except tomllib.TOMLDecodeError:
        custom = {}
    with tempfile.TemporaryDirectory(prefix="ii-matugen-test-") as tmp:
        out = Path(tmp) / "out" / (Path(entry["output"]).name or "rendered")
        lines = ["[config]", "version_check = false"]
        if custom:
            lines.append("[config.custom_colors]")
            for key, value in custom.items():
                if isinstance(value, str):
                    lines.append(f"{toml_key(key)} = {toml_string(value)}")
        # No hooks: a test must not reload apps or run anything.
        lines += ["[templates.test]",
                  f"input_path = {toml_string(str(expand(entry['input'])))}",
                  f"output_path = {toml_string(str(out))}"]
        cfg = Path(tmp) / "config.toml"
        cfg.write_text("\n".join(lines) + "\n", encoding="utf-8")
        try:
            proc = subprocess.run(
                [*matugen_command(), "color", "hex", color, "--mode", mode, "-c", str(cfg)],
                capture_output=True, text=True, timeout=30,
            )
        except FileNotFoundError as exc:
            raise ManagerError("Matugen is not installed", "no_matugen") from exc
        except subprocess.TimeoutExpired as exc:
            raise ManagerError("Matugen took more than 30 s", "timeout") from exc
        log = ANSI_RE.sub("", (proc.stderr or "") + (proc.stdout or "")).strip()
        if not out.exists():
            # Matugen often exits 0 after a render error: the missing file is the tell.
            message = clean_error(log) or f"Matugen exited with {proc.returncode}"
            raise ManagerError(message, "render_failed")
        rendered = out.read_text(encoding="utf-8", errors="replace")
    preview = rendered.splitlines()[:40]
    return {"name": args.name, "mode": mode, "color": color, "preview": "\n".join(preview),
            "lines": len(rendered.splitlines()), "bytes": len(rendered.encode())}


def clean_error(log: str) -> str:
    keep = []
    for line in log.splitlines():
        text = line.strip(" │╭╰─[]")
        if not text or "Backtrace" in text or "RUST_BACKTRACE" in text or "folder doesnt exist" in text:
            continue
        keep.append(line.rstrip())
    return "\n".join(keep[:12])


# ── Themes ─────────────────────────────────────────────────────────────────


def ensure_custom_colors(doc: Document, colors: dict) -> list[str]:
    """Add the custom colours a theme needs to [config.custom_colors]."""
    existing = doc.parsed().get("config", {}).get("custom_colors", {})
    missing = {k: v for k, v in colors.items() if k not in existing}
    if not missing:
        return []
    new_lines = [f"{toml_key(k)} = {toml_string(v)}" for k, v in missing.items()]
    headers = doc._headers()
    for idx, (line_no, key, disabled) in enumerate(headers):
        if not disabled and key == ["config", "custom_colors"]:
            end = headers[idx + 1][0] if idx + 1 < len(headers) else len(doc.lines)
            while end > line_no + 1 and doc._is_trivia(doc.lines[end - 1], False):
                end -= 1
            doc.lines[end:end] = new_lines
            return list(missing)
    if "custom_colors" in doc.parsed().get("config", {}):
        raise ManagerError("custom_colors is written inline; add the colours in config.toml", "not_editable")
    # After the [config] table, or at the top when there is none.
    insert_at = 0
    for idx, (line_no, key, disabled) in enumerate(headers):
        if not disabled and key == ["config"]:
            end = headers[idx + 1][0] if idx + 1 < len(headers) else len(doc.lines)
            while end > line_no + 1 and doc._is_trivia(doc.lines[end - 1], False):
                end -= 1
            insert_at = end
            break
    block = ["", "[config.custom_colors]", *new_lines]
    if insert_at == 0:
        block = ["[config.custom_colors]", *new_lines, ""]
    doc.lines[insert_at:insert_at] = block
    return list(missing)


def catalog_comment(theme: dict) -> str:
    return f"# {theme['name']} theme from the ii catalog."


def find_theme(theme_id: str) -> dict:
    for theme in load_catalog():
        if theme["id"] == theme_id:
            return theme
    raise ManagerError(f"no theme '{theme_id}' in the catalog", "not_found")


def cmd_install_theme(args) -> dict:
    theme = find_theme(args.id)
    doc, original = load_with_original()
    templates = list_templates(doc)
    if any(t["theme"] == theme["id"] for t in templates):
        raise ManagerError("this theme is already set up", "exists")
    name = theme["id"]
    if doc.find(name) or name in doc.parsed().get("templates", {}):
        raise ManagerError(f"a template named '{name}' already exists", "exists")
    source = CATALOG_DIR / theme["template"]
    dest = config_dir() / "templates" / "ii-themes" / Path(theme["template"]).name
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, dest)
    added = ensure_custom_colors(doc, theme.get("customColors", {}))
    while doc.lines and not doc.lines[-1].strip():
        doc.lines.pop()
    if doc.lines:
        doc.lines.append("")
    doc.lines.append(catalog_comment(theme))
    doc.lines.extend(render_block(name, {
        "input_path": contract(dest), "output_path": theme["output"], "post_hook": theme.get("postHook", ""),
    }))
    save(doc, original)
    return {"name": name, "addedColors": added}


def cmd_uninstall_theme(args) -> dict:
    theme = find_theme(args.id)
    doc, _ = load_with_original()
    match = next((t for t in list_templates(doc) if t["theme"] == theme["id"]), None)
    if match is None:
        raise ManagerError("this theme is not set up", "not_found")
    if not match["fromCatalog"]:
        raise ManagerError(f"'{match['name']}' is your own template; manage it in the list below", "not_catalog")
    # Its catalog comment goes too, when it sits right above the block.
    return cmd_remove(argparse.Namespace(name=match["name"], delete_input=True), catalog_comment(theme))


# ── File picker ────────────────────────────────────────────────────────────


def cmd_pick_file(args) -> dict:
    start = str(config_dir() / "templates") + "/"
    candidates = []
    if shutil.which("zenity"):
        cmd = ["zenity", "--file-selection", f"--filename={start}"]
        if args.save:
            cmd.append("--save")
        candidates.append(cmd)
    if shutil.which("kdialog"):
        candidates.append(["kdialog", "--getsavefilename" if args.save else "--getopenfilename", start])
    if not candidates:
        raise ManagerError("install zenity or kdialog to browse for files", "no_picker")
    proc = subprocess.run(candidates[0], capture_output=True, text=True)
    path = proc.stdout.strip()
    return {"path": contract(path) if path else "", "cancelled": not path}


# ── Entry point ────────────────────────────────────────────────────────────


def cmd_list(_args) -> dict:
    path = config_path()
    try:
        doc = Document.load()
        doc.parsed()
        error = ""
    except tomllib.TOMLDecodeError as exc:
        error = str(exc)
    templates = list_templates(doc) if not error else []
    return {
        "config": contract(path),
        "configExists": path.exists(),
        "configError": error,
        "templatesDir": contract(config_dir() / "templates"),
        "templates": templates,
        "themes": catalog_entries(templates),
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("list")
    add = sub.add_parser("add")
    add.add_argument("name")
    add.add_argument("--input", required=True)
    add.add_argument("--output", required=True)
    add.add_argument("--pre-hook", default="")
    add.add_argument("--post-hook", default="")
    add.add_argument("--create", action="store_true", help="write a starter template at --input")
    upd = sub.add_parser("update")
    upd.add_argument("name")
    upd.add_argument("--rename")
    upd.add_argument("--input")
    upd.add_argument("--output")
    upd.add_argument("--pre-hook")
    upd.add_argument("--post-hook")
    rem = sub.add_parser("remove")
    rem.add_argument("name")
    rem.add_argument("--delete-input", action="store_true")
    for verb in ("enable", "disable"):
        sub.add_parser(verb).add_argument("name")
    test = sub.add_parser("test")
    test.add_argument("name")
    test.add_argument("--mode", choices=["dark", "light"])
    test.add_argument("--color")
    sub.add_parser("install-theme").add_argument("id")
    sub.add_parser("uninstall-theme").add_argument("id")
    pick = sub.add_parser("pick-file")
    pick.add_argument("--save", action="store_true")
    return parser


def run(argv: list[str]) -> tuple[int, dict]:
    args = build_parser().parse_args(argv)
    handlers = {
        "list": cmd_list,
        "add": cmd_add,
        "update": cmd_update,
        "remove": cmd_remove,
        "enable": lambda a: cmd_toggle(a.name, True),
        "disable": lambda a: cmd_toggle(a.name, False),
        "test": cmd_test,
        "install-theme": cmd_install_theme,
        "uninstall-theme": cmd_uninstall_theme,
        "pick-file": cmd_pick_file,
    }
    try:
        return 0, {"ok": True, **handlers[args.command](args)}
    except ManagerError as exc:
        return 1, {"ok": False, "error": str(exc), "code": exc.code}
    except OSError as exc:
        return 1, {"ok": False, "error": f"{exc.strerror or exc}: {exc.filename or ''}".strip(": "), "code": "os_error"}


def main() -> int:
    status, payload = run(sys.argv[1:])
    print(json.dumps(payload, ensure_ascii=False))
    return status


if __name__ == "__main__":
    sys.exit(main())
