#!/usr/bin/env python3
"""Backend of the sidebar's Anki tab (services/Anki.qml).

Runs inside ~/.local/share/ii-anki/venv (scripts/anki/install.sh) and drives the
official `anki` package: the same Rust core as Anki desktop, so the queue, the
FSRS/SM-2 scheduling, the rendered card HTML and the AnkiWeb sync are Anki's own.

Protocol: one JSON object per line. Requests on stdin `{"id": n, "cmd": "...", ...}`;
replies on stdout `{"id": n, "ok": true, "data": ...}` or `{"id": n, "ok": false,
"error": "..."}`; unsolicited `{"event": "..."}` lines for progress.

The HTML the reviewer would feed a web view is reshaped here for Qt's rich text
(a subset of HTML 4 + CSS 2.1, no scripts): MathJax becomes inline SVG images,
<ruby> becomes reading-in-brackets, sizes are clamped to the sidebar, colours that
only make sense on Anki's white page are dropped, and [[type:]] / [anki:play:]
markers become data the tab draws with its own controls.
"""

import html
from html.parser import HTMLParser
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
import traceback

DATA_DIR = os.path.join(os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share")), "ii-anki")
CACHE_DIR = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "ii-anki")
COLLECTION = os.environ.get("II_ANKI_COLLECTION") or os.path.join(DATA_DIR, "collection", "collection.anki2")
AUTH_FILE = os.path.join(DATA_DIR, "auth.json")
MATH_DIR = os.path.join(CACHE_DIR, "math")
MATHJAX_DIR = os.path.join(DATA_DIR, "mathjax")
HERE = os.path.dirname(os.path.abspath(__file__))

_out_lock = threading.Lock()


def emit(obj):
    with _out_lock:
        sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
        sys.stdout.flush()


def log(*args):
    print("[anki]", *args, file=sys.stderr, flush=True)


# ── MathJax ────────────────────────────────────────────────────────────────

class MathRenderer:
    """TeX → SVG files through a lazily started node process, cached on disk by
    (tex, display, colour). Missing node/MathJax degrades to the TeX source."""

    def __init__(self):
        self.proc = None
        self.failed = False
        os.makedirs(MATH_DIR, exist_ok=True)

    @property
    def available(self):
        return (not self.failed and shutil.which("node") is not None
                and os.path.isdir(os.path.join(MATHJAX_DIR, "node_modules", "mathjax-full")))

    def _ensure(self):
        if self.proc and self.proc.poll() is None:
            return True
        if not self.available:
            return False
        script = os.path.join(MATHJAX_DIR, "tex2svg.mjs")
        src = os.path.join(HERE, "tex2svg.mjs")
        # Keep the copy next to node_modules in step with the repo.
        try:
            if not os.path.exists(script) or open(src).read() != open(script).read():
                shutil.copyfile(src, script)
        except OSError:
            pass
        try:
            self.proc = subprocess.Popen(["node", script], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                         stderr=subprocess.DEVNULL, text=True, bufsize=1)
            return True
        except OSError as e:
            log("mathjax start failed:", e)
            self.failed = True
            return False

    def render(self, tex, display, color, font_px):
        key = hashlib.sha1(f"{tex}\0{display}\0{color}\0{font_px}".encode()).hexdigest()[:20]
        path = os.path.join(MATH_DIR, key + ".svg")
        meta = path + ".json"
        if os.path.exists(path) and os.path.exists(meta):
            try:
                return path, json.load(open(meta))
            except (OSError, ValueError):
                pass
        if not self._ensure():
            return None, None
        try:
            self.proc.stdin.write(json.dumps({"tex": tex, "display": display}) + "\n")
            self.proc.stdin.flush()
            reply = json.loads(self.proc.stdout.readline() or "{}")
        except (OSError, ValueError) as e:
            log("mathjax:", e)
            self.proc = None
            return None, None
        svg = reply.get("svg")
        if not svg:
            return None, None
        # MathJax sizes in ex; Qt's SVG loader wants pixels. One ex of the card font
        # is ~0.45 em for the sans faces the tab uses.
        ex = font_px * 0.45
        dims = {}

        def px(m):
            dims[m.group(1)] = round(float(m.group(2)) * ex, 1)
            return f'{m.group(1)}="{dims[m.group(1)]}px"'

        svg = re.sub(r'(width|height)="([\d.]+)ex"', px, svg, count=2)
        valign = re.search(r'vertical-align:\s*(-?[\d.]+)ex', svg)
        dims["valign"] = round(float(valign.group(1)) * ex, 1) if valign else 0
        svg = re.sub(r'\sstyle="[^"]*"', "", svg, count=1)
        svg = svg.replace("currentColor", color)
        with open(path, "w") as f:
            f.write(svg)
        with open(meta, "w") as f:
            json.dump(dims, f)
        return path, dims

    def close(self):
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()


# ── HTML reshaping ─────────────────────────────────────────────────────────

RE_SCRIPT = re.compile(r"<script\b.*?</script\s*>", re.S | re.I)
RE_STYLE = re.compile(r"<style\b[^>]*>(.*?)</style\s*>", re.S | re.I)
RE_MATH = re.compile(r"\\\((.+?)\\\)|\\\[(.+?)\\\]", re.S)
RE_RUBY = re.compile(r"<ruby\b[^>]*>(.*?)</ruby\s*>", re.S | re.I)
RE_RT = re.compile(r"<rt\b[^>]*>(.*?)</rt\s*>", re.S | re.I)
RE_RP = re.compile(r"<rp\b[^>]*>.*?</rp\s*>", re.S | re.I)
RE_TAG = re.compile(r"<[^>]+>")
RE_IMG = re.compile(r"<img\b([^>]*?)/?>", re.I | re.S)
RE_ATTR = re.compile(r'([\w-]+)\s*=\s*("([^"]*)"|\'([^\']*)\'|([^\s>]+))', re.S)
RE_STYLE_ATTR = re.compile(r'\sstyle\s*=\s*("([^"]*)"|\'([^\']*)\')', re.I)
RE_FONT_COLOR = re.compile(r'(<font\b[^>]*?)\scolor\s*=\s*("[^"]*"|\'[^\']*\'|[^\s>]+)', re.I)
RE_PLAY = re.compile(r"\[anki:play:[qa]:\d+\]")
RE_TYPE = re.compile(r"\[\[type:([^\]]+)\]\]")
RE_ANSWER_HR = re.compile(r"<hr\s+id\s*=\s*[\"']?answer[\"']?\s*/?>", re.I)
RE_CSS_RULE = re.compile(r"([^{}]+)\{([^{}]*)\}")


def _luminance(color):
    """Relative luminance of a CSS colour, or None when it can't be parsed."""
    c = color.strip().lower()
    named = {"black": (0, 0, 0), "white": (255, 255, 255), "#000": (0, 0, 0), "#fff": (255, 255, 255)}
    rgb = named.get(c)
    if rgb is None:
        m = re.fullmatch(r"#([0-9a-f]{6})", c)
        if m:
            rgb = tuple(int(m.group(1)[i:i + 2], 16) for i in (0, 2, 4))
        else:
            m = re.fullmatch(r"#([0-9a-f]{3})", c)
            if m:
                rgb = tuple(int(ch * 2, 16) for ch in m.group(1))
            else:
                m = re.fullmatch(r"rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)[^)]*\)", c)
                if m:
                    rgb = tuple(int(x) for x in m.groups())
    if rgb is None:
        return None
    return (0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]) / 255


def _neutral(color):
    """Black/white-ish colours: written for Anki's white page, unreadable on the theme."""
    lum = _luminance(color)
    return lum is not None and (lum < 0.18 or lum > 0.9)


def clean_style_attr(style):
    decls = []
    for decl in style.split(";"):
        if ":" not in decl:
            continue
        prop, value = decl.split(":", 1)
        prop = prop.strip().lower()
        if prop in ("background", "background-color", "font-family", "line-height", "width", "height",
                    "max-width", "min-width", "position", "float"):
            continue
        if prop == "color" and _neutral(value):
            continue
        decls.append(f"{prop}:{value.strip()}")
    return ";".join(decls)


def clean_css(css):
    """Card CSS minus what fights the theme: page colours, fonts and sizes on the
    page-level selectors, and night-mode overrides (the tab is always themed)."""
    out = []
    for selectors, body in RE_CSS_RULE.findall(css):
        sel = selectors.strip()
        if not sel or sel.startswith("@"):
            continue
        if "nightmode" in sel.lower() or "night_mode" in sel.lower():
            continue
        page_level = bool(re.search(r"(^|[\s,])(\.card|body|html|\*)\b", sel))
        decls = []
        for decl in body.split(";"):
            if ":" not in decl:
                continue
            prop, value = decl.split(":", 1)
            prop = prop.strip().lower()
            if prop in ("background", "background-color", "position", "display", "flex", "gap", "transform",
                        "transition", "animation", "opacity", "cursor", "box-shadow", "filter"):
                continue
            if page_level and prop in ("color", "font-family", "font-size", "line-height", "margin", "padding", "text-align"):
                continue
            if prop == "color" and _neutral(value):
                continue
            decls.append(f"{prop}:{value.strip()}")
        if decls:
            out.append(f"{sel}{{{';'.join(decls)}}}")
    return "\n".join(out)


# ── Card CSS that decides structure ────────────────────────────────────────
# Qt's rich text has no display:none and sizes images only from attributes, so the
# rules a web view would apply to hide variants (light/dark logos, JS-picked
# examples) and to size images are resolved here and baked into the HTML.

RE_NIGHT = re.compile(r"(:root\s*)?(\.night[-_]?mode|\.nightMode|\.night_mode|\[data-bs-theme=['\"]?dark['\"]?\]|:root\.night-mode)", re.I)
RE_SIMPLE = re.compile(r"^([a-z][a-z0-9]*)?((?:[.#][\w-]+)*)$", re.I)
CONTEXT_PARTS = {":root", "html", "body", ".card", "article.card", "*"}


def _css_px(value, font_px):
    m = re.fullmatch(r"\s*(-?[\d.]+)\s*(px|em|rem)?\s*(!important)?\s*", value)
    if not m:
        return None
    n = float(m.group(1))
    return n * font_px if m.group(2) in ("em", "rem") else n


class StructuralCss:
    """The subset of a note type's CSS that changes which elements exist and how big
    images are: per simple selector (tag, .class, #id, combos), the final `display`
    and the width/height limits, with night-mode rules applied only in dark mode."""

    def __init__(self, css, dark, font_px):
        self.rules = []  # (tag, classes, id, decls) in source order
        css = re.sub(r"/\*.*?\*/", "", css, flags=re.S)
        for selectors, body in RE_CSS_RULE.findall(css):
            decls = {}
            for decl in body.split(";"):
                if ":" in decl:
                    k, v = decl.split(":", 1)
                    decls[k.strip().lower()] = v.strip()
            keep = {k: v for k, v in decls.items()
                    if k in ("display", "width", "height", "max-width", "max-height", "visibility")}
            if not keep:
                continue
            for sel in selectors.split(","):
                sel = sel.strip()
                if not sel or sel.startswith("@"):
                    continue
                night = bool(RE_NIGHT.search(sel))
                if night != dark and night:
                    continue
                sel = RE_NIGHT.sub(" ", sel)
                parts = [p for p in re.split(r"\s+|>", sel) if p and p not in CONTEXT_PARTS]
                if len(parts) != 1:
                    # Descendant selectors: only the context-free ones are safe to
                    # apply without a real cascade.
                    continue
                m = RE_SIMPLE.match(parts[0])
                if not m:
                    continue
                tag = (m.group(1) or "").lower()
                classes = set(re.findall(r"\.([\w-]+)", m.group(2) or ""))
                ids = re.findall(r"#([\w-]+)", m.group(2) or "")
                if not tag and not classes and not ids:
                    continue
                parsed = dict(keep)
                for k in ("width", "height", "max-width", "max-height"):
                    if k in parsed:
                        parsed[k] = _css_px(parsed[k], font_px)
                self.rules.append((tag, classes, ids[0] if ids else None, parsed))

    def resolve(self, tag, attrs):
        classes = set((attrs.get("class") or "").split())
        el_id = attrs.get("id")
        out = {}
        for rtag, rclasses, rid, decls in self.rules:
            if rtag and rtag != tag:
                continue
            if rclasses and not rclasses <= classes:
                continue
            if rid and rid != el_id:
                continue
            for k, v in decls.items():
                if v is not None:
                    out[k] = v
        style = attrs.get("style") or ""
        for decl in style.split(";"):
            if ":" in decl:
                k, v = decl.split(":", 1)
                k = k.strip().lower()
                if k == "display":
                    out[k] = v.strip()
                elif k in ("width", "height", "max-width", "max-height"):
                    px = _css_px(v, 18)
                    if px is not None:
                        out[k] = px
        return out


VOID_TAGS = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}
DROP_TAGS = {"script", "style", "svg", "template", "noscript", "button", "input", "select", "textarea", "iframe", "object", "video", "audio"}


class _Node:
    __slots__ = ("tag", "attrs", "children", "text")

    def __init__(self, tag=None, attrs=None, text=None):
        self.tag, self.attrs, self.children, self.text = tag, attrs or [], [], text


class _TreeBuilder(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=False)
        self.root = _Node("#root")
        self.stack = [self.root]

    def handle_starttag(self, tag, attrs):
        node = _Node(tag, attrs)
        self.stack[-1].children.append(node)
        if tag not in VOID_TAGS:
            self.stack.append(node)

    def handle_startendtag(self, tag, attrs):
        self.stack[-1].children.append(_Node(tag, attrs))

    def handle_endtag(self, tag):
        for i in range(len(self.stack) - 1, 0, -1):
            if self.stack[i].tag == tag:
                del self.stack[i:]
                return

    def handle_data(self, data):
        self.stack[-1].children.append(_Node(text=data))

    def handle_entityref(self, name):
        self.stack[-1].children.append(_Node(text=f"&{name};"))

    def handle_charref(self, name):
        self.stack[-1].children.append(_Node(text=f"&#{name};"))

    def handle_comment(self, data):
        pass


def _attr_str(attrs):
    out = []
    for k, v in attrs:
        out.append(f" {k}" if v is None else f' {k}="{html.escape(v, quote=True)}"')
    return "".join(out)


class Reshaper:
    def __init__(self, media_dir, math):
        self.media_dir = media_dir
        self.math = math
        self.max_width = 380
        self.font_px = 18
        self.color = "#e6e0e9"
        self.dark = True
        self._sizes = {}

    def image_size(self, name):
        path = name if os.path.isabs(name) else os.path.join(self.media_dir, name)
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            return None, None
        hit = self._sizes.get(path)
        if hit and hit[0] == mtime:
            return hit[1], path
        size = None
        try:
            from PIL import Image
            with Image.open(path) as im:
                size = im.size
        except Exception:
            if path.lower().endswith(".svg"):
                head = open(path, errors="ignore").read(2048)
                w = re.search(r'width="([\d.]+)', head)
                h = re.search(r'height="([\d.]+)', head)
                if w and h:
                    size = (float(w.group(1)), float(h.group(1)))
        self._sizes[path] = (mtime, size)
        return size, path

    def _img(self, attrs, rules):
        """An <img> as Qt can draw it: local file URL, explicit pixel size from the
        attributes or the note CSS (contained, like object-fit), clamped to the column."""
        src = html.unescape(attrs.get("src") or "")
        if not src or re.match(r"^(https?|data):", src, re.I):
            # Remote and inline images: Qt's rich text can't fetch them.
            alt = attrs.get("alt") or ""
            return f'<i>[{html.escape(alt)}]</i>' if alt else ""
        src = src.split("?")[0]
        size, path = self.image_size(src)
        nat_w, nat_h = size if size else (None, None)

        def num(v):
            try:
                return float(v)
            except (TypeError, ValueError):
                return None

        box_w = rules.get("width") or num(attrs.get("width"))
        box_h = rules.get("height") or num(attrs.get("height"))
        w = h = None
        if nat_w and nat_h:
            if box_w and box_h:
                k = min(box_w / nat_w, box_h / nat_h)  # object-fit: contain
                w, h = nat_w * k, nat_h * k
            elif box_w:
                w, h = box_w, nat_h * box_w / nat_w
            elif box_h:
                w, h = nat_w * box_h / nat_h, box_h
            else:
                w, h = nat_w, nat_h
        elif box_w and box_h:
            w, h = box_w, box_h
        if w:
            limits = [self.max_width, rules.get("max-width") or self.max_width]
            max_w = min(x for x in limits if x)
            if w > max_w:
                h, w = h * max_w / w, max_w
            max_h = min(480, rules.get("max-height") or 480)
            # Very tall images would push the answer off the sidebar.
            if h > max_h:
                w, h = w * max_h / h, max_h
        url = "file://" + (path or os.path.join(self.media_dir, src))
        dims = f' width="{int(round(w))}" height="{int(round(h))}"' if w else ""
        return f'<img src="{html.escape(url, quote=True)}"{dims}>'

    def _structure(self, text, css):
        """Drop what a browser would not show (hidden attribute, display:none from
        the note CSS or inline style, unrenderable widgets) and size images."""
        rules_css = StructuralCss(css, self.dark, self.font_px)
        builder = _TreeBuilder()
        builder.feed(text)
        builder.close()
        out = []

        def walk(node):
            for child in node.children:
                if child.tag is None:
                    out.append(child.text)
                    continue
                attrs = {k.lower(): v for k, v in child.attrs}
                if child.tag in DROP_TAGS or "hidden" in attrs:
                    continue
                rules = rules_css.resolve(child.tag, attrs)
                display = (rules.get("display") or "").replace("!important", "").strip().lower()
                if display == "none":
                    continue
                if child.tag == "img":
                    out.append(self._img(attrs, rules))
                    continue
                out.append(f"<{child.tag}{_attr_str(child.attrs)}>")
                if child.tag in VOID_TAGS:
                    continue
                walk(child)
                out.append(f"</{child.tag}>")

        walk(builder.root)
        return "".join(out)

    def _math(self, m):
        display = m.group(2) is not None
        tex = html.unescape(m.group(2) if display else m.group(1)).strip()
        tex = tex.replace("<br>", " ").replace("<br/>", " ")
        tex = RE_TAG.sub("", tex)
        path, dims = self.math.render(tex, display, self.color, self.font_px) if self.math else (None, None)
        if not path:
            return f'<code>{html.escape(tex)}</code>'
        # data-ii-math lets the tab rescale formulas to the side's text size.
        img = f'<img data-ii-math="1" src="file://{path}" width="{dims.get("width", 0)}" height="{dims.get("height", 0)}" align="middle">'
        return f'<div align="center">{img}</div>' if display else img

    @staticmethod
    def _ruby(m):
        inner = RE_RP.sub("", m.group(1))
        readings = [RE_TAG.sub("", r).strip() for r in RE_RT.findall(inner)]
        base = RE_TAG.sub("", RE_RT.sub("", inner)).strip()
        reading = "".join(readings)
        if not reading:
            return base
        return f'{base}<span class="ii-ruby">({html.escape(reading)})</span>'

    def reshape(self, text, css=""):
        text = RE_SCRIPT.sub("", text)
        extra_css = "\n".join(RE_STYLE.findall(text))
        text = RE_STYLE.sub("", text)
        text = RE_PLAY.sub("", text)
        # Structure and media images first: the math images added next point at the
        # cache, not the media folder.
        text = self._structure(text, css + "\n" + extra_css)
        text = RE_MATH.sub(self._math, text)
        text = RE_RUBY.sub(self._ruby, text)
        text = RE_STYLE_ATTR.sub(lambda m: (lambda s: f' style="{s}"' if s else "")(
            clean_style_attr(m.group(2) if m.group(2) is not None else m.group(3))), text)
        text = RE_FONT_COLOR.sub(lambda m: m.group(1) if _neutral(m.group(2).strip("\"'")) else m.group(0), text)
        return text.strip(), extra_css


# ── Collection ─────────────────────────────────────────────────────────────

class Daemon:
    def __init__(self):
        from anki.collection import Collection
        os.makedirs(os.path.dirname(COLLECTION), exist_ok=True)
        self.Collection = Collection
        self.col = Collection(COLLECTION)
        self.math = MathRenderer()
        self.shaper = Reshaper(self.col.media.dir(), self.math)
        self.current = None  # (card, states, queue kind) of the card on screen
        self.auth = self._load_auth()
        self.media_thread = None

    # helpers ---------------------------------------------------------------
    def _load_auth(self):
        try:
            d = json.load(open(AUTH_FILE))
            return d if d.get("hkey") else None
        except (OSError, ValueError):
            return None

    def _sync_auth(self):
        from anki.sync import SyncAuth
        if not self.auth:
            raise RuntimeError("not-logged-in")
        return SyncAuth(hkey=self.auth["hkey"], endpoint=self.auth.get("endpoint") or None)

    def _save_auth(self):
        os.makedirs(DATA_DIR, exist_ok=True)
        fd = os.open(AUTH_FILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            json.dump(self.auth, f)

    def _deck_rows(self):
        tree = self.col.sched.deck_due_tree()
        rows = []

        def walk(node, depth, path):
            for child in node.children:
                full = f"{path}::{child.name}" if path else child.name
                rows.append({
                    "id": child.deck_id, "name": child.name, "fullName": full, "depth": depth,
                    "new": child.new_count, "learn": child.learn_count, "review": child.review_count,
                    "total": child.total_in_deck, "collapsed": child.collapsed,
                    "hasChildren": len(child.children) > 0, "filtered": child.filtered,
                })
                walk(child, depth + 1, full)

        walk(tree, 0, "")
        # The empty "Default" deck is noise once real decks exist (Anki hides it too).
        if len(rows) > 1:
            rows = [r for r in rows if not (r["id"] == 1 and r["total"] == 0 and not r["hasChildren"])]
        return rows

    def _totals(self, rows):
        top = [r for r in rows if r["depth"] == 0]
        return {k: sum(r[k] for r in top) for k in ("new", "learn", "review")}

    def _labels(self, states):
        try:
            return [s.replace("⁨", "").replace("⁩", "") for s in self.col.sched.describe_next_states(states)]
        except Exception:
            return ["", "", "", ""]

    def _type_field(self, card, qhtml):
        m = RE_TYPE.search(qhtml)
        if not m:
            return None
        name = m.group(1)
        cloze = name.startswith("cloze:")
        fname = name.split(":", 1)[1] if ":" in name else name
        note = card.note()
        if fname not in note.keys():
            return None
        expected = note[fname]
        if cloze:
            ords = re.findall(r"\{\{c%d::(.+?)(?:::.*?)?\}\}" % (card.ord + 1), expected)
            expected = ", ".join(ords)
        expected = html.unescape(RE_TAG.sub("", expected.replace("<br>", "\n"))).strip()
        return {"field": fname, "expected": expected}

    def _av(self, tags):
        out = []
        for t in tags:
            fn = getattr(t, "filename", None)
            if fn:
                out.append({"kind": "file", "path": os.path.join(self.col.media.dir(), fn), "name": fn})
            elif getattr(t, "field_text", None) is not None:
                out.append({"kind": "tts", "text": RE_TAG.sub("", t.field_text), "lang": getattr(t, "lang", "")})
        return out

    def _card_payload(self, reveal_typed=None):
        card, states, kind = self.current
        out = card.render_output(reload=True)
        qraw, araw = out.question_text, out.answer_text
        type_info = self._type_field(card, qraw)
        q, qcss = self.shaper.reshape(RE_TYPE.sub("", qraw), out.css)
        # Answer side: split off the FrontSide part when the template has the usual
        # <hr id=answer>; cloze answers repeat the whole text, revealed, instead.
        aparts = RE_ANSWER_HR.split(araw, maxsplit=1)
        split = len(aparts) == 2
        abody = aparts[1] if split else araw
        if type_info:
            typed = reveal_typed if reveal_typed is not None else ""
            cmp = self.col.compare_answer(type_info["expected"], typed)
            abody = RE_TYPE.sub(lambda _m: cmp, abody, count=1)
            abody = RE_TYPE.sub("", abody)
        else:
            abody = RE_TYPE.sub("", abody)
        a, acss = self.shaper.reshape(abody, out.css)
        conf = self.col.decks.config_dict_for_deck_id(card.current_deck_id())
        counts = self.col.sched.counts()
        note = card.note()
        return {
            "cardId": card.id, "noteId": card.nid,
            "deck": self.col.decks.name(card.current_deck_id()),
            "question": q, "answer": a, "answerSplit": split,
            "css": clean_css(out.css + "\n" + qcss + "\n" + acss),
            "labels": self._labels(states), "queue": kind,
            "counts": {"new": counts[0], "learn": counts[1], "review": counts[2]},
            "audioQ": self._av(out.question_av_tags), "audioA": self._av(out.answer_av_tags),
            "autoplay": bool(conf.get("autoplay", True)), "replayQuestion": bool(conf.get("replayq", True)),
            "typeIn": {"field": type_info["field"]} if type_info else None,
            "flag": card.user_flag(), "marked": note.has_tag("marked"),
            "model": card.note_type()["name"],
        }

    def _next(self):
        q = self.col.sched.get_queued_cards(fetch_limit=1)
        if not q.cards:
            self.current = None
            return None
        qc = q.cards[0]
        from anki.cards import Card
        card = Card(self.col, backend_card=qc.card)
        card.start_timer()
        kind = {0: "new", 1: "learn", 2: "review"}.get(int(qc.queue), "review")
        self.current = (card, qc.states, kind)
        return self._card_payload()

    def _require_current(self, card_id):
        if not self.current or self.current[0].id != card_id:
            raise RuntimeError("stale-card")

    # commands --------------------------------------------------------------
    def cmd_hello(self, req):
        from anki.buildinfo import version
        return {"version": version, "collection": COLLECTION, "loggedIn": bool(self.auth),
                "username": (self.auth or {}).get("username", ""), "mathjax": self.math.available,
                "cards": self.col.card_count()}

    def cmd_theme(self, req):
        self.shaper.color = req.get("color", self.shaper.color)
        self.shaper.font_px = int(req.get("fontPx", self.shaper.font_px))
        self.shaper.max_width = int(req.get("maxWidth", self.shaper.max_width))
        self.shaper.dark = bool(req.get("dark", self.shaper.dark))
        return True

    def cmd_decks(self, req):
        rows = self._deck_rows()
        return {"decks": rows, "totals": self._totals(rows), "cards": self.col.card_count(),
                "studiedToday": self._studied_today()}

    def _studied_today(self):
        cutoff = (self.col.sched.day_cutoff - 86400) * 1000
        row = self.col.db.first("select count(), coalesce(sum(time), 0) from revlog where id > ?", cutoff)
        return {"cards": row[0], "seconds": round(row[1] / 1000)}

    def cmd_study(self, req):
        self.col.decks.select(int(req["deckId"]))
        return self._next()

    def cmd_current(self, req):
        if not self.current:
            return self._next()
        return self._card_payload()

    def cmd_reveal(self, req):
        self._require_current(int(req["cardId"]))
        return self._card_payload(reveal_typed=req.get("typed", ""))

    def cmd_answer(self, req):
        self._require_current(int(req["cardId"]))
        card, states, _ = self.current
        ease = int(req["ease"])
        if ease not in (1, 2, 3, 4):
            raise ValueError("ease must be 1-4")
        from anki.scheduler.v3 import CardAnswer
        rating = [CardAnswer.AGAIN, CardAnswer.HARD, CardAnswer.GOOD, CardAnswer.EASY][ease - 1]
        self.col.sched.answer_card(self.col.sched.build_answer(card=card, states=states, rating=rating))
        return self._next()

    def cmd_undo(self, req):
        try:
            self.col.undo()
        except Exception as e:
            raise RuntimeError("nothing-to-undo") from e
        return self._next()

    def cmd_bury(self, req):
        self._require_current(int(req["cardId"]))
        if req.get("note"):
            self.col.sched.bury_notes([self.current[0].nid])
        else:
            self.col.sched.bury_cards([self.current[0].id], manual=True)
        return self._next()

    def cmd_suspend(self, req):
        self._require_current(int(req["cardId"]))
        self.col.sched.suspend_cards([self.current[0].id])
        return self._next()

    def cmd_flag(self, req):
        self._require_current(int(req["cardId"]))
        self.col.set_user_flag_for_cards(int(req["flag"]), [self.current[0].id])
        self.current[0].load()
        return self._card_payload()

    def cmd_mark(self, req):
        self._require_current(int(req["cardId"]))
        note = self.current[0].note()
        if note.has_tag("marked"):
            note.remove_tag("marked")
        else:
            note.add_tag("marked")
        self.col.update_note(note)
        return self._card_payload()

    def cmd_createDeck(self, req):
        name = req["name"].strip()
        if not name:
            raise ValueError("empty-name")
        return {"id": self.col.decks.id(name)}

    def cmd_noteTypes(self, req):
        return [{"id": m["id"], "name": m["name"], "fields": [f["name"] for f in m["flds"]],
                 "cloze": m.get("type") == 1} for m in self.col.models.all()]

    def cmd_addNote(self, req):
        model = self.col.models.get(int(req["noteTypeId"])) if req.get("noteTypeId") else self.col.models.by_name("Basic")
        note = self.col.new_note(model)
        fields = req.get("fields", [])
        for i, value in enumerate(fields[:len(note.fields)]):
            note.fields[i] = html.escape(value).replace("\n", "<br>") if req.get("plain", True) else value
        tags = req.get("tags", "").split()
        note.tags = tags
        problem = note.fields_check()
        if problem:
            raise ValueError(f"note-check-{int(problem)}")
        self.col.add_note(note, int(req["deckId"]))
        return {"noteId": note.id, "cards": len(note.card_ids())}

    def cmd_importApkg(self, req):
        from anki.import_export_pb2 import ImportAnkiPackageOptions, ImportAnkiPackageRequest
        path = req["path"]
        if path.startswith("file://"):
            path = path[7:]
        res = self.col.import_anki_package(ImportAnkiPackageRequest(
            package_path=path,
            options=ImportAnkiPackageOptions(merge_notetypes=True, with_scheduling=True, with_deck_configs=True)))
        lg = res.log
        return {"new": len(lg.new), "updated": len(lg.updated), "duplicate": len(lg.duplicate)}

    def cmd_login(self, req):
        auth = self.col.sync_login(req["username"].strip(), req["password"], None)
        self.auth = {"hkey": auth.hkey, "endpoint": auth.endpoint if auth.HasField("endpoint") else "",
                     "username": req["username"].strip()}
        self._save_auth()
        return {"username": self.auth["username"]}

    def cmd_logout(self, req):
        self.auth = None
        try:
            os.remove(AUTH_FILE)
        except OSError:
            pass
        return True

    def cmd_sync(self, req):
        from anki.sync_pb2 import SyncCollectionResponse as R
        auth = self._sync_auth()
        emit({"event": "sync", "stage": "collection"})
        out = self.col.sync_collection(auth, sync_media=False)
        if out.HasField("new_endpoint") and out.new_endpoint:
            self.auth["endpoint"] = out.new_endpoint
            self._save_auth()
            auth = self._sync_auth()
        required = int(out.required)
        result = {"message": out.server_message, "full": None}
        empty_local = self.col.card_count() == 0
        if required == R.FULL_DOWNLOAD or (required == R.FULL_SYNC and empty_local):
            self._full(auth, out.server_media_usn, upload=False)
            result["full"] = "download"
        elif required == R.FULL_UPLOAD:
            self._full(auth, out.server_media_usn, upload=True)
            result["full"] = "upload"
        elif required == R.FULL_SYNC:
            # Both sides changed in a way that can't merge: the user picks.
            self.pending_full_usn = out.server_media_usn
            return {"conflict": True, "message": out.server_message}
        self._media(auth)
        self.current = None
        return result

    def cmd_fullSync(self, req):
        auth = self._sync_auth()
        self._full(auth, getattr(self, "pending_full_usn", None), upload=bool(req["upload"]))
        self._media(auth)
        self.current = None
        return {"full": "upload" if req["upload"] else "download"}

    def _full(self, auth, server_usn, upload):
        emit({"event": "sync", "stage": "upload" if upload else "download"})
        self.col.close_for_full_sync()
        try:
            self.col.full_upload_or_download(auth=auth, server_usn=server_usn, upload=upload)
        finally:
            self.col.reopen(after_full_sync=True)
        self.shaper.media_dir = self.col.media.dir()

    def _media(self, auth):
        emit({"event": "sync", "stage": "media"})
        try:
            self.col.sync_media(auth)
        except Exception as e:
            log("media sync:", e)

    def cmd_mediaStatus(self, req):
        st = self.col.media_sync_status()
        return {"active": st.active}

    def cmd_play(self, req):
        path = req["path"]
        if not os.path.realpath(path).startswith(os.path.realpath(self.col.media.dir()) + os.sep):
            raise ValueError("outside-media")
        self._stop_audio()
        player = shutil.which("mpv")
        cmd = [player, "--no-video", "--really-quiet", "--no-terminal", path] if player else ["pw-play", path]
        self.audio = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True

    def _stop_audio(self):
        p = getattr(self, "audio", None)
        if p and p.poll() is None:
            p.terminate()

    def cmd_stopAudio(self, req):
        self._stop_audio()
        return True

    def close(self):
        self._stop_audio()
        self.math.close()
        try:
            self.col.close()
        except Exception:
            pass


def main():
    try:
        d = Daemon()
    except Exception as e:
        msg = str(e)
        kind = "locked" if "locked" in msg.lower() or "busy" in msg.lower() else "open-failed"
        emit({"event": "fatal", "kind": kind, "error": msg})
        return 1
    emit({"event": "ready"})
    try:
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                req = json.loads(line)
            except ValueError:
                continue
            rid = req.get("id")
            if req.get("cmd") == "quit":
                emit({"id": rid, "ok": True, "data": True})
                break
            fn = getattr(d, "cmd_" + str(req.get("cmd")), None)
            if not fn:
                emit({"id": rid, "ok": False, "error": "unknown-command"})
                continue
            t0 = time.monotonic()
            try:
                emit({"id": rid, "ok": True, "data": fn(req)})
            except Exception as e:
                name = type(e).__name__
                msg = str(e) or name
                if name in ("SyncError", "NetworkError"):
                    msg = f"{name}: {msg}"
                log(req.get("cmd"), "failed:", msg)
                if os.environ.get("II_ANKI_DEBUG"):
                    traceback.print_exc(file=sys.stderr)
                emit({"id": rid, "ok": False, "error": msg, "kind": name})
            dt = time.monotonic() - t0
            if dt > 0.25:
                log(req.get("cmd"), f"took {dt:.2f}s")
    finally:
        d.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
