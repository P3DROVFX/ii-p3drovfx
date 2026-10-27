#!/usr/bin/env python3
"""Landmarks for the Settings search: the visible words of a page that are not cloneable controls.

SearchRegistry clones ``ContentSection``s and their ``Config*`` controls, which is all a
page used to be made of. The redesigned pages draw their headings on hero cards, panes,
tiles and chips (``ColorsPalettePane``'s "Color scheme"), so a query for any of them
found nothing. A landmark is such a string with the page that shows it; the search
result is a link that opens the page and flashes the text, not a clone.

Each page is crawled from its file and its registered sub-pages through every settings
component they instantiate (ColorsThemesConfig -> ColorsPalettePane -> ...). This runs
out of process: scanning ~270 files in the shell's JS engine held its UI thread for
seconds.

Usage: search_landmarks.py <shell root> '<pages JSON: [{id, component, subPages}]>'
Prints {"landmarks": [{pageId, subPage, key, subPageTitle}]}; keys are untranslated.
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

CONFIGS = "modules/settings/configs/"

# Prose rather than names: a word inside one of these is not where a user expects
# the setting to be called that, and they would bury the real hits.
PROSE_PROPS = {
    "tooltip", "description", "summary", "hint", "message", "body", "helperText",
    "supportingText", "placeholder", "placeholderText", "subtitle", "explanation",
    "detail", "details", "caption", "warning", "toolTipText", "infoText",
}
MAX_CHARS = 48
MAX_WORDS = 6
MAX_DEPTH = 6

TR_RE = re.compile(r"""Translation\.tr\(\s*("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')""")
TYPE_RE = re.compile(r"(^|[^\w.])([A-Z][A-Za-z0-9_]*)\s*\{")
IMPORT_RE = re.compile(r"""^\s*import\s+(?:"([^"]+)"|(qs(?:\.[A-Za-z_]\w*)+))""", re.M)
ROW_RE = re.compile(r"ConfigSubpageRow\s*\{")
STRING_RE = re.compile(r""""(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|`(?:\\.|[^`\\])*`""")
COMMENT_OR_STRING_RE = re.compile(
    r"""//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|`(?:\\.|[^`\\])*`""", re.S)
# A quoted key too: option chips are object literals ({ "displayName": ... }).
PROP_RE = re.compile(r"""["']?([A-Za-z_]\w*)["']?\s*:\s*[^:]*$""")
LINE_PROP_RE = re.compile(r"^\s*([A-Za-z_][\w.]*)\s*:")


def blank(s: str, fill: str = " ") -> str:
    return "\n".join(fill * len(part) for part in s.split("\n"))


def strip_comments(text: str) -> str:
    """Comments carry quotes and braces that are not code ("the user's ...").
    Blanked to the same length, so offsets still point into the original text."""
    return COMMENT_OR_STRING_RE.sub(lambda m: m.group(0) if m.group(0)[0] in "\"'`" else blank(m.group(0)), text)


def mask_strings(code: str) -> str:
    """String contents blanked, same length: only code is left to scan for braces and ids."""
    return STRING_RE.sub(lambda m: m.group(0)[0] + blank(m.group(0)[1:-1], "x") + m.group(0)[-1], code)


def unquote(literal: str) -> str:
    body = literal[1:-1]
    return re.sub(r"\\([\"'\\])", r"\1", body).replace("\\n", " ")


def is_landmark_text(s: str) -> bool:
    s = s.strip()
    if len(s) < 2 or len(s) > MAX_CHARS:
        return False
    # Templates ("%1 · customized") are filled in at runtime.
    if re.search(r"%\d", s):
        return False
    if not re.search(r"[A-Za-z\u00C0-\u024F]{2}", s):
        return False
    # A sentence is a description, not a name; "Checking…" is a status.
    if s[-1] in ".!?:…":
        return False
    return len(s.split()) <= MAX_WORDS


def property_for(code: str, offset: int) -> str:
    """The property a string is bound to: the nearest `name:` before it on its line."""
    line_start = code.rfind("\n", 0, offset) + 1
    before = code[line_start:offset]
    m = PROP_RE.search(before)
    if m:
        return m.group(1)
    m = LINE_PROP_RE.match(before)
    return m.group(1) if m else ""


def extract_landmarks(text: str) -> list[str]:
    """Short translated strings bound to a property in this file, in source order."""
    code = strip_comments(text)
    found: list[str] = []
    for m in TR_RE.finditer(code):
        s = unquote(m.group(1)).strip()
        if not is_landmark_text(s):
            continue
        # A string a function computes (`return ...`, `parts.push(...)`) is a runtime
        # label chosen among others; only bound ones are fixed names.
        prop = property_for(code, m.start())
        if not prop or prop.split(".")[-1] in PROSE_PROPS:
            continue
        # `.arg(...)` fills the string in at runtime; it never shows as written.
        if re.match(r"\s*\)\s*\.arg\b", code[m.end():m.end() + 12]):
            continue
        if s not in found:
            found.append(s)
    return found


def referenced_types(text: str) -> list[str]:
    code = STRING_RE.sub('""', strip_comments(text))
    types: list[str] = []
    for m in TYPE_RE.finditer(code):
        if m.group(2) not in types:
            types.append(m.group(2))
    return types


def import_dirs(text: str, file_path: str, shell_root: str) -> list[str]:
    """Its own directory and each local import (`qs.modules.settings.configs.colors`, `"colors"`)."""
    own = os.path.dirname(file_path) + "/"
    dirs = [own]
    for m in IMPORT_RE.finditer(strip_comments(text)):
        if m.group(1):
            if m.group(1).endswith(".js"):
                continue
            d = os.path.normpath(own + m.group(1)) + "/"
        else:
            d = shell_root + "/".join(m.group(2).split(".")[1:]) + "/"
        if d not in dirs:
            dirs.append(d)
    return dirs


def child_files(text: str, file_path: str, shell_root: str, file_set: set[str]) -> list[str]:
    """Settings components this file instantiates. Common widgets are not crawled:
    their strings are generic and they belong to every page."""
    dirs = import_dirs(text, file_path, shell_root)
    files: list[str] = []
    for t in referenced_types(text):
        for d in dirs:
            candidate = d + t + ".qml"
            if candidate != file_path and candidate in file_set:
                if candidate not in files:
                    files.append(candidate)
                break
    return files


# A sub-page a file opens: a row's `configPage`, an `openSubPage(...)`, an
# `activeSubPage = ...`, by a file name written out.
SUB_PAGE_REF_RE = re.compile(
    r"""(?:configPage\s*:|openSubPage\(|activeSubPage\s*=)\s*(?:Qt\.resolvedUrl\(\s*)?["']([\w./-]+\.qml)["']""")


def needs_opener(path: str, text: str | None) -> bool:
    """A sub-page that only works for what its opener hands it - a bind to edit, a
    network, the app being picked for - is no place for a search result to land."""
    # The root object's own: a delegate's `required property var modelData` is not.
    return (text is None or bool(re.search(r"^    required property\b", text, re.M))
            or bool(re.search(r"(Editor|Picker)(Page)?$", Path(path).stem)))


OPENER_LABEL_RE = re.compile(r"""\b(?:title|text|mainText)\s*:\s*Translation\.tr\(\s*("(?:\\.|[^"\\])*")""")


def sub_page_refs(text: str, file_path: str, configs: str, file_set: set[str]) -> list[tuple[str, str]]:
    """Files under configs/ this file opens as sub-pages, each with the label of the
    row that opens it ("" if none is near). A page's own helper often adds the folder
    (`openSubPage("ThemedIconsConfig.qml")` opens widgets/...), so the name is looked
    for next to the file, then in its widgets/, then from configs/."""
    here = os.path.dirname(file_path) + "/"
    code = strip_comments(text)
    found: list[tuple[str, str]] = []
    for m in SUB_PAGE_REF_RE.finditer(code):
        ref = m.group(1)
        for base in (here, here + "widgets/", configs, configs + "widgets/"):
            candidate = os.path.normpath(base + ref)
            if candidate in file_set:
                if candidate != os.path.normpath(file_path) and all(candidate != f for f, _ in found):
                    labels = OPENER_LABEL_RE.findall(code[max(0, m.start() - 400):m.start()])
                    found.append((candidate, unquote(labels[-1]) if labels else ""))
                break
    return found


def block_after(code: str, start: int) -> str:
    depth, j, quote = 1, start, ""
    while j < len(code) and depth > 0:
        ch = code[j]
        if quote:
            if ch == "\\":
                j += 1
            elif ch == quote:
                quote = ""
        elif ch in "\"'`":
            quote = ch
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
        j += 1
    return code[start:j]


def sub_page_titles(text: str, file_path: str) -> dict[str, str]:
    """Titles of the rows that open a sub-page, by the sub-page's absolute path."""
    code = strip_comments(text)
    titles: dict[str, str] = {}
    for m in ROW_RE.finditer(code):
        block = block_after(code, m.end())
        page = re.search(r'configPage\s*:\s*(?:Qt\.resolvedUrl\(\s*)?"([^"]+\.qml)"', block)
        title = re.search(r'title\s*:\s*Translation\.tr\(\s*"((?:\\.|[^"\\])*)"', block)
        if page and title:
            titles[os.path.normpath(os.path.dirname(file_path) + "/" + page.group(1))] = unquote('"' + title.group(1) + '"')
    return titles


def fallback_title(sub_page: str) -> str:
    """"widgets/WallpaperEngineConfig.qml" -> "Wallpaper Engine", for a sub-page no row names."""
    base = re.sub(r"Config$", "", Path(sub_page).stem)
    base = re.sub(r"([a-z0-9])([A-Z])", r"\1 \2", base)
    return re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1 \2", base)


# ── Presentable components ─────────────────────────────────────────────────
#
# A landmark drawn by a settings component (a pane, a tile, a hero card) can be
# shown in the results as that component, cloned from the page the way the
# registry clones a ConfigSwitch: the usage block, with the page's imports. The
# block may lean on the page's ids; the ones that can be stood in for are:
# geometry read from a sibling (`width: tiles.tileWidth`: a literal property is
# inlined, anything else is dropped and the clone fills the row), and the page
# root's `activeSubPage`, which the clone routes to the sub-page. Any other
# outside id leaves the landmark a link.

OBJECT_RE = re.compile(r"(?<![\w.])([A-Z][A-Za-z0-9_]*)\s*\{")
ID_RE = re.compile(r"\bid\s*:\s*([A-Za-z_]\w*)")
GEOMETRY_RE = re.compile(r"^\s*(width|height|x|y|implicitWidth|implicitHeight|anchors(?:\.\w+)?|Layout\.\w+)\s*:\s*(.+?)\s*;?\s*$")
LITERAL_PROP_RE = re.compile(r"^\s*(?:readonly\s+)?property\s+\w+\s+(\w+)\s*:\s*(-?\d+(?:\.\d+)?)\s*;?\s*$")
WIDTH_PROPS = ("width", "Layout.fillWidth", "Layout.preferredWidth", "anchors.fill", "anchors.left", "anchors.right")
DELEGATE_HOSTS = {"Repeater", "ListView", "GridView", "Instantiator", "PathView", "TableView", "Component"}
QT5COMPAT_RE = re.compile(r"^\s*import\s+Qt5Compat", re.M)


def object_blocks(masked: str) -> list[tuple[str, int, int, int]]:
    """(type, start, open brace, end) of every object in comment- and string-masked code."""
    # One pass: every brace pairs with its closer; objects are the braces a type opens.
    closer: dict[int, int] = {}
    stack = []
    for m in re.finditer(r"[{}]", masked):
        if m.group(0) == "{":
            stack.append(m.start())
        elif stack:
            closer[stack.pop()] = m.end()
    blocks = []
    for m in OBJECT_RE.finditer(masked):
        brace = m.end() - 1
        blocks.append((m.group(1), m.start(), brace, closer.get(brace, len(masked))))
    return blocks


def top_level_lines(masked: str, brace: int, end: int) -> list[tuple[int, int]]:
    """(start, end) of the lines that begin directly inside a block, one level deep."""
    lines, depth, i = [], 0, brace + 1
    line_start = i
    while i < end - 1:
        ch = masked[i]
        if ch == "\n":
            line_start = i + 1
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
        if i == line_start and depth == 0:
            eol = masked.find("\n", i)
            eol = end - 1 if eol == -1 or eol > end - 1 else eol
            lines.append((i, eol))
        i += 1
    return lines


class RootFile:
    """A page or sub-page file, parsed once for the component blocks it holds."""

    def __init__(self, path: str, text: str, shell_root: str, file_set: set[str]):
        self.path = path
        self.text = text
        self.code = strip_comments(text)
        self.masked = mask_strings(self.code)
        self.blocks = object_blocks(self.masked)
        self.dirs = import_dirs(text, path, shell_root)
        self.file_set = file_set
        self.imports = "\n".join(l.strip() for l in text.splitlines() if l.strip().startswith("import "))
        self.qt5compat = bool(QT5COMPAT_RE.search(text))
        self.id_positions = {m.group(1): m.start() for m in ID_RE.finditer(self.masked)}
        self.ids = list(self.id_positions)
        self.root_id = ""
        if self.blocks:
            first = self.blocks[0]
            for a, b in top_level_lines(self.masked, first[2], first[3]):
                m = re.match(r"^\s*id\s*:\s*([A-Za-z_]\w*)", self.masked[a:b])
                if m:
                    self.root_id = m.group(1)
                    break
        self._literals: dict[str, dict[str, str]] = {}

    def literals(self, ident: str) -> dict[str, str]:
        """Numeric literal properties of the object that declares `ident`."""
        if ident not in self._literals:
            pos = self.id_positions.get(ident, -1)
            owner = None
            for block in self.blocks:
                if block[2] < pos < block[3] and (owner is None or block[2] > owner[2]):
                    owner = block
            props = {}
            if owner:
                for a, b in top_level_lines(self.masked, owner[2], owner[3]):
                    m = LITERAL_PROP_RE.match(self.masked[a:b])
                    if m:
                        props[m.group(1)] = m.group(2)
            self._literals[ident] = props
        return self._literals[ident]

    def local_file(self, type_name: str) -> str:
        for d in self.dirs:
            candidate = d + type_name + ".qml"
            if candidate != self.path and candidate in self.file_set:
                return candidate
        return ""

    def outermost_component(self, offset: int):
        """The outermost settings component (not the page root) enclosing `offset`."""
        for block in self.blocks[1:]:
            type_name, start, _, end = block
            if start <= offset < end and self.local_file(type_name):
                return block
        return None


def uses_qt5compat(path: str, read, shell_root: str, file_set: set[str], memo: dict, stack=()) -> bool:
    """Qt5Compat effects pin a dead window and crash the shell once a clone is
    destroyed with its window (see the Qt5Compat memory); such components stay links."""
    if path in memo:
        return memo[path]
    if path in stack:
        return False
    text = read(path) or ""
    result = bool(QT5COMPAT_RE.search(text)) or any(
        uses_qt5compat(child, read, shell_root, file_set, memo, stack + (path,))
        for child in child_files(text, path, shell_root, file_set))
    memo[path] = result
    return result


def presentable_block(root: RootFile, block, read, shell_root: str, file_set: set[str], memo: dict) -> dict | None:
    type_name, start, brace, end = block
    if root.qt5compat:
        return None
    for t in referenced_types(root.text[start:end]):
        f = root.local_file(t)
        if f and uses_qt5compat(f, read, shell_root, file_set, memo):
            return None

    masked = root.masked
    lines = top_level_lines(masked, brace, end)
    # A block that hides itself (`visible: style === "expressive"`) would leave an
    # empty result card whenever the condition is off.
    if any(re.match(r"^\s*visible\s*:", masked[a:b]) for a, b in lines):
        return None
    # An overlay anchored over the page is not a card to list.
    if any(re.match(r"^\s*anchors\.(fill|centerIn)\s*:", masked[a:b]) for a, b in lines):
        return None
    # A delegate is one of many and reads its model entry.
    if re.search(r"\b(modelData|model\.|index)\b", masked[start:end]) or any(
            t in DELEGATE_HOSTS and s < start and e > end for t, s, _, e in root.blocks):
        return None
    inner_ids = set(ID_RE.findall(masked[start:end]))
    outside = [i for i in dict.fromkeys(root.ids) if i not in inner_ids]
    edits: dict[tuple[int, int], str | None] = {}
    shim = False
    for ident in outside:
        pattern = re.compile(r"\b" + re.escape(ident) + r"\b")
        for m in pattern.finditer(masked, start, end):
            if ident == root.root_id and re.match(r"\.activeSubPage\b", masked[m.end():m.end() + 15]):
                shim = True
                continue
            line = next(((a, b) for a, b in lines if a <= m.start() < b), None)
            geometry = GEOMETRY_RE.match(masked[line[0]:line[1]]) if line else None
            if not geometry or "{" in masked[line[0]:line[1]]:
                return None
            value = geometry.group(2)
            ref = re.fullmatch(re.escape(ident) + r"\.(\w+)", value)
            literal = root.literals(ident).get(ref.group(1)) if ref else None
            edits[line] = root.text[line[0]:line[0] + geometry.start(2)] + literal if literal else None

    source = ""
    cursor = start
    kept_props = []
    for a, b in lines:
        if (a, b) in edits:
            source += root.text[cursor:a] + (edits[(a, b)] or "")
            cursor = b
        name = GEOMETRY_RE.match(masked[a:b])
        if name and edits.get((a, b), "") is not None:
            kept_props.append(name.group(1))
    source += root.text[cursor:end - 1]
    if not any(p in WIDTH_PROPS for p in kept_props):
        source += "\n    Layout.fillWidth: true\n"
    source += "}"
    return {
        "type": type_name,
        "source": source,
        "imports": root.imports,
        "dir": os.path.dirname(root.path) + "/",
        "rootId": root.root_id if shim else "",
    }


def crawl(shell_root: str, pages: list[dict], blocks: dict | None = None,
          discovered: list[dict] | None = None) -> list[dict]:
    """Landmarks of every page. With `blocks`, each landmark a settings component
    draws also names (`block`) the clone source stored there. With `discovered`,
    the sub-pages found by their opener and registered nowhere ({pageId, subPage})
    are listed there, for their controls to be indexed too."""
    shell_root = shell_root.rstrip("/") + "/"
    configs = shell_root + CONFIGS
    file_set = {os.path.join(d, f) for d, _, fs in os.walk(configs) for f in fs if f.endswith(".qml")}
    texts: dict[str, str] = {}
    titles: dict[str, str] = {}
    landmarks: list[dict] = []
    # Every file a page already names; a row linking to one is not a sub-page of its own.
    registered = {os.path.normpath(shell_root + p["component"]) for p in pages}
    for p in pages:
        registered.update(os.path.normpath(configs + f) for f in (p.get("subPages") or []) + (p.get("searchSources") or [])
                          + list((p.get("searchSubPages") or {}).values()))

    def read(path: str) -> str | None:
        if path not in texts:
            try:
                texts[path] = Path(path).read_text(encoding="utf-8")
            except OSError:
                texts[path] = None
        return texts[path]

    roots: dict[str, RootFile] = {}
    qt5_memo: dict[str, bool] = {}
    block_memo: dict[str, str] = {}

    def component_for(root_path: str, via: str, key: str) -> str:
        if root_path not in roots:
            roots[root_path] = RootFile(root_path, read(root_path) or "", shell_root, file_set)
        root = roots[root_path]
        if via:
            usage = next((b for b in root.blocks if b[0] == via), None)
            offset = usage[1] if usage else -1
        else:
            m = re.search(r"Translation\.tr\(\s*[\"']" + re.escape(key) + r"[\"']", root.code)
            offset = m.start() if m else -1
        block = root.outermost_component(offset) if offset >= 0 else None
        if not block:
            return ""
        block_id = root_path + ":" + str(block[1])
        if block_id not in block_memo:
            built = presentable_block(root, block, read, shell_root, file_set, qt5_memo)
            block_memo[block_id] = block_id if built else ""
            if built:
                blocks[block_id] = built
        return block_memo[block_id]

    for page in pages:
        seen: set[tuple[str, str]] = set()
        # (file, sub-page, depth, root file, the root's child type it was reached through)
        queue = [(shell_root + page["component"], "", 0, shell_root + page["component"], "")]
        queue += [(configs + sub, sub, 0, configs + sub, "") for sub in page.get("subPages") or []]
        # Sections drawn outside the page file (tabs, progressive sections) show on
        # the page, or on the sub-page they stand in for.
        queue += [(configs + src, (page.get("searchSubPages") or {}).get(src, ""), 0, configs + src, "")
                  for src in page.get("searchSources") or []]
        visited: set[tuple[str, str]] = set()
        while queue:
            path, sub_page, depth, root_path, via = queue.pop(0)
            if (path, sub_page) in visited:
                continue
            visited.add((path, sub_page))
            text = read(path)
            if text is None:
                continue
            titles.update(sub_page_titles(text, path))
            for ref, label in sub_page_refs(text, path, configs, file_set):
                if ref in registered:
                    continue
                registered.add(ref)
                if needs_opener(ref, read(ref)):
                    continue
                if label:
                    titles.setdefault(ref, label)
                sub = os.path.relpath(ref, configs)
                queue.append((ref, sub, 0, ref, ""))
                if discovered is not None:
                    discovered.append({"pageId": page["id"], "subPage": sub})
            for key in extract_landmarks(text):
                if (sub_page, key) in seen:
                    continue
                seen.add((sub_page, key))
                landmark = {"pageId": page["id"], "subPage": sub_page, "key": key}
                if blocks is not None:
                    block_id = component_for(root_path, via, key)
                    if block_id:
                        landmark["block"] = block_id
                landmarks.append(landmark)
            if depth < MAX_DEPTH:
                for child in child_files(text, path, shell_root, file_set):
                    queue.append((child, sub_page, depth + 1, root_path, via or Path(child).stem))

    for lm in landmarks:
        sub = lm["subPage"]
        lm["subPageTitle"] = (titles.get(os.path.normpath(configs + sub)) or fallback_title(sub)) if sub else ""
    return landmarks


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    pages = [p for p in json.loads(argv[2]) if p.get("searchable") is not False]
    blocks: dict = {}
    discovered: list[dict] = []
    landmarks = crawl(argv[1], pages, blocks, discovered)
    json.dump({"landmarks": landmarks, "blocks": blocks, "subPages": discovered}, sys.stdout, ensure_ascii=False)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
