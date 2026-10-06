#!/usr/bin/env python3
"""
recolor_icons.py — Dynamic Material You Icon Theme Generator

Pipeline:
  1. Recolor the base icon theme (SVG, PNG and base64-in-SVG) into DynamicTheme
  2. Scavenge icons the base theme lacks from .desktop files (absolute paths, hicolor,
     pixmaps, loose files at the root of an icon dir, other themes)
  3. Inject everything into DynamicTheme so the system treats them as native

How a colour is chosen (tone mapping, the Material You way):
  The scheme only gives the hue and chroma: primary and secondary become HCT tonal
  palettes, and every output colour is read off them at a tone this script picks. So the
  light/dark mode of the scheme does not matter (icons always come out in the dark-mode
  look), and anything that changes hue or chroma — wallpaper, Intense's boosted chroma,
  custom themes, picked key colours — carries over without special cases.

  App icons are normalised one by one before that. Each is measured (rendered, for SVGs)
  and classified as a *plate* icon (a squircle/circle background carrying a logo) or a
  *glyph* icon (a bare shape on transparency). Plates always land on the same dark
  container tone with the logo above it, glyphs on the same light tone; an icon drawn the
  other way round (white plate, dark logo) is flipped first. That is what makes an icon
  pack that mixes white, black and transparent backgrounds come out as one family.
  Everything else (actions, status, places, symbolic icons) keeps its own tones and only
  takes the palette's hue, so light/dark UI glyphs keep reading against their toolbars.
"""
import os
import sys
import json
import re
import io
import base64
import bisect
import shutil
import subprocess
import tempfile
import configparser
import glob
import hashlib
import fcntl
import uuid
from concurrent.futures import ProcessPoolExecutor

# --force skips the "nothing changed" early-exit and always regenerates
FORCE = "--force" in sys.argv

# Bump when the colour mapping changes so an unchanged scheme still regenerates once.
ALGORITHM_VERSION = 2


# ── Paths ────────────────────────────────────────────────────────────────────
CONFIG_JSON = os.path.expanduser("~/.config/illogical-impulse/config.json")
COLORS_JSON = os.path.expanduser("~/.local/state/quickshell/user/generated/colors.json")
TARGET_THEME_PATH = os.path.expanduser("~/.local/share/icons/DynamicTheme")


def _xdg_data_dirs():
    dirs = [os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")]
    dirs += (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")
    dirs += [
        "/usr/local/share",
        "/usr/share",
        "/var/lib/flatpak/exports/share",
        os.path.expanduser("~/.local/share/flatpak/exports/share"),
        "/var/lib/snapd/desktop",
    ]
    seen, out = set(), []
    for d in dirs:
        d = os.path.realpath(d) if d else ""
        if d and d not in seen:
            seen.add(d)
            out.append(d)
    return out


ICON_SEARCH_DIRS = [os.path.expanduser("~/.icons")] + [os.path.join(d, "icons") for d in _xdg_data_dirs()]
PIXMAP_DIRS = [os.path.join(d, "pixmaps") for d in _xdg_data_dirs()]
DESKTOP_SEARCH_DIRS = [os.path.join(d, "applications") for d in _xdg_data_dirs()]

# Base theme context folders that get recolored
RECOLOR_CONTEXTS = ["apps", "places", "categories", "devices", "status", "actions", "preferences"]
# Of those, the ones whose icons are normalised one by one (full-colour app art)
APP_CONTEXTS = ("apps", "preferences")


# ── Config & Colors ─────────────────────────────────────────────────────────
def get_config():
    try:
        if os.path.exists(CONFIG_JSON):
            with open(CONFIG_JSON, 'r') as f:
                return json.load(f)
    except Exception as e:
        print(f"Error reading config: {e}")
    return {}


def get_colors():
    """The scheme switchwall just wrote — overrides, custom themes and the Intense boost
    already applied. Only hue and chroma are read from it, so either mode works."""
    try:
        if os.path.exists(COLORS_JSON):
            with open(COLORS_JSON, 'r') as f:
                data = json.load(f)
            if "colors" in data:
                data = data["colors"]
                if "dark" in data:
                    return data["dark"]
                if "light" in data:
                    return data["light"]
            return data
    except Exception as e:
        print(f"Error reading colors: {e}")
    return None


# ── Colour science ──────────────────────────────────────────────────────────
import numpy as np

_SRGB_TO_XYZ = np.array([[0.4124564, 0.3575761, 0.1804375],
                         [0.2126729, 0.7151522, 0.0721750],
                         [0.0193339, 0.1191920, 0.9503041]])
_WHITE = np.array([0.95047, 1.0, 1.08883])


_SRGB_LINEAR = np.array([c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
                         for c in np.arange(256) / 255.0], dtype=np.float32)
_SRGB_TO_XYZ_W = (_SRGB_TO_XYZ.T / _WHITE).astype(np.float32)


def lab_tone_chroma(rgb):
    """CIELAB L* (= HCT tone) and a*b* chroma of an (..., 3) array of 0-255 values."""
    rgb = np.asarray(rgb)
    if rgb.dtype == np.uint8:
        lin = _SRGB_LINEAR[rgb]
    else:
        c = np.clip(rgb.astype(np.float32), 0, 255) / 255.0
        lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4).astype(np.float32)
    xyz = lin @ _SRGB_TO_XYZ_W
    f = np.where(xyz > 216 / 24389, np.cbrt(xyz), (24389 / 27 * xyz + 16) / 116)
    tone = 116 * f[..., 1] - 16
    chroma = np.hypot(500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2]))
    return tone, chroma


def _hex_to_rgb(value):
    value = value.lstrip('#')
    if len(value) in (3, 4):
        value = ''.join(ch * 2 for ch in value)
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


# Same keys the scheme exposes for each family; the most chromatic one carries the
# palette's key chroma (a tone near black or white is clipped by the gamut).
_FAMILIES = {
    "primary": ["primary", "primary_container", "on_primary_container", "primary_fixed",
                "primary_fixed_dim", "on_primary_fixed_variant", "inverse_primary", "surface_tint"],
    "secondary": ["secondary", "secondary_container", "on_secondary_container", "secondary_fixed",
                  "secondary_fixed_dim", "on_secondary_fixed_variant"],
}


class Palette:
    """Two tonal palettes (primary, secondary) sampled every 0.5 tone."""
    TONES = np.linspace(0, 100, 201)

    def __init__(self, colors):
        self.keys = {}
        self.tables = {}
        self._lut = None
        for family, names in _FAMILIES.items():
            hue_chroma = self._key(colors, names)
            self.keys[family] = (round(hue_chroma[0]), round(hue_chroma[1])) if hue_chroma else None
            self.tables[family] = self._table(hue_chroma, colors, names)

    @staticmethod
    def _key(colors, names):
        try:
            from materialyoucolor.hct import Hct
        except ImportError:
            return None
        best = None
        for name in names:
            value = colors.get(name)
            if not isinstance(value, str) or not value.startswith('#'):
                continue
            r, g, b = _hex_to_rgb(value)
            hct = Hct.from_int(0xff000000 | (r << 16) | (g << 8) | b)
            if best is None or hct.chroma > best[1]:
                best = (hct.hue, hct.chroma)
        return best

    def _table(self, hue_chroma, colors, names):
        if hue_chroma:
            from materialyoucolor.palettes.tonal_palette import TonalPalette
            palette = TonalPalette.from_hue_and_chroma(hue_chroma[0], hue_chroma[1])
            rows = []
            for t in self.TONES:
                argb = palette.tone(float(t))
                rows.append(((argb >> 16) & 255, (argb >> 8) & 255, argb & 255))
            return np.array(rows, dtype=np.float32)
        # No materialyoucolor: interpolate the scheme's own colours by tone
        samples = [(0.0, (0, 0, 0)), (100.0, (255, 255, 255))]
        for name in names:
            value = colors.get(name)
            if isinstance(value, str) and value.startswith('#'):
                rgb = _hex_to_rgb(value)
                samples.append((float(lab_tone_chroma(rgb)[0]), rgb))
        samples.sort()
        xs = [s[0] for s in samples]
        return np.stack([np.interp(self.TONES, xs, [s[1][i] for s in samples]) for i in range(3)],
                        axis=-1).astype(np.float32)

    def fingerprint(self):
        return self.keys

    def sample(self, tone, weight):
        """Colour at `tone` mixed from secondary (weight 0) to primary (weight 1), as uint8.
        One gather from a (tone × weight) table: this runs on every pixel of every icon."""
        if self._lut is None:
            mix = np.linspace(0.0, 1.0, 33, dtype=np.float32)[None, :, None]
            lut = self.tables["secondary"][:, None, :] * (1 - mix) + self.tables["primary"][:, None, :] * mix
            self._lut = np.clip(np.rint(lut), 0, 255).astype(np.uint8)
        t = np.rint(np.clip(tone, 0, 100) * 2).astype(np.intp)
        w = np.rint(np.clip(weight, 0, 1) * 32).astype(np.intp)
        return self._lut[t, w]


class ToneMap:
    """How one icon's tones land on the palette.

    plate: background squircle → PLATE_TONE, logo above it
    glyph: bare shape → GLYPH_TONE
    keep:  tones untouched, only the hue changes (UI glyphs, symbolic icons)
    """
    PLATE_TONE = 30.0   # primary_container in a dark scheme
    GLYPH_TONE = 80.0   # primary in a dark scheme

    def __init__(self, kind="keep", invert=False, xs=(0.0, 100.0), ys=(0.0, 100.0), anchor=None):
        self.kind = kind
        self.invert = invert
        self.xs = list(xs)
        self.ys = list(ys)
        self.anchor = anchor  # the (post-flip) source tone of the plate

    def apply(self, tone, chroma, alpha_hint=None):
        """Map source tone/chroma arrays to (output tone, primary weight)."""
        src = 100.0 - tone if self.invert else tone
        out = np.interp(src, self.xs, self.ys)
        # Colourful source → primary, greys → mostly secondary (still tinted)
        weight = 0.35 + 0.65 * np.clip((chroma - 4.0) / 26.0, 0.0, 1.0)
        if self.kind == "plate" and self.anchor is not None:
            # The plate itself takes one fixed mix whatever its source colour, so a grey
            # plate and a blue plate end up the same container colour.
            k = np.clip(1.0 - np.abs(src - self.anchor) / 12.0, 0.0, 1.0)
            weight = weight * (1 - k) + 0.8 * k
        if self.kind == "keep":
            # Near-black/near-white UI glyph colours stay neutral-ish
            weight = weight * np.clip(np.minimum(tone, 100 - tone) / 15.0, 0.3, 1.0)
        return out, weight


def _weighted_quantile(values, weights, q):
    order = np.argsort(values)
    v = values[order]
    cw = np.cumsum(weights[order])
    if cw[-1] <= 0:
        return float(np.median(values))
    return float(np.interp(q * cw[-1], cw, v))


def analyze_tones(tone, weight, coverage):
    """Classify an icon from its visible pixels and build its ToneMap.
    tone/weight: L* and alpha of the visible pixels; coverage: alpha-weighted canvas share."""
    if tone.size < 4 or weight.sum() <= 0:
        return ToneMap("glyph", False, (0, 100), (ToneMap.GLYPH_TONE - 30, ToneMap.GLYPH_TONE + 15))

    median = _weighted_quantile(tone, weight, 0.5)
    near = weight[np.abs(tone - median) <= 12].sum() / weight.sum()
    plate = coverage >= 0.40 and near >= 0.30

    if plate:
        content = np.abs(tone - median) > 10
        content_share = weight[content].sum() / weight.sum()
        if content_share < 0.02:
            invert = median > 50
        else:
            invert = np.average(tone[content], weights=weight[content]) < median
    else:
        invert = median < 50

    t = 100.0 - tone if invert else tone
    ref = 100.0 - median if invert else median
    lo = min(_weighted_quantile(t, weight, 0.01), ref)
    hi = max(_weighted_quantile(t, weight, 0.99), ref)

    if plate:
        base = ToneMap.PLATE_TONE
        y_lo = max(6.0, base - (ref - lo) * 0.8)
        y_hi = min(94.0, base + min(62.0, max(45.0, (hi - ref) * 2.0)))
    else:
        base = ToneMap.GLYPH_TONE
        y_lo = max(25.0, base - (ref - lo) * 1.1)
        y_hi = min(96.0, base + max(8.0, (hi - ref) * 1.0))

    xs, ys = [lo - 0.5, ref, hi + 0.5], [y_lo, base, y_hi]
    return ToneMap("plate" if plate else "glyph", bool(invert), xs, ys, ref if plate else None)


def analyze_image(img):
    """ToneMap for a PIL image (an app icon), measured on a 64 px copy."""
    from PIL import Image
    small = img.convert("RGBA")
    small.thumbnail((64, 64), Image.Resampling.BILINEAR)
    canvas = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    canvas.paste(small, ((64 - small.width) // 2, (64 - small.height) // 2))
    arr = np.asarray(canvas, dtype=np.uint8)
    alpha = arr[..., 3] / 255.0
    visible = alpha > 0.05
    tone, _ = lab_tone_chroma(arr[..., :3][visible])
    return analyze_tones(tone, alpha[visible], alpha.sum() / alpha.size)


def render_svg(path_or_bytes, size=64):
    """Rasterise an SVG with resvg for measuring. None when resvg is missing or fails."""
    if not shutil.which("resvg"):
        return None
    try:
        from PIL import Image
        if isinstance(path_or_bytes, (bytes, bytearray)):
            res = subprocess.run(["resvg", "-w", str(size), "-h", str(size), "-", "-c"],
                                 input=path_or_bytes, capture_output=True, timeout=20)
        else:
            res = subprocess.run(["resvg", "-w", str(size), "-h", str(size), path_or_bytes, "-c"],
                                 capture_output=True, timeout=20)
        if res.returncode != 0 or not res.stdout:
            return None
        return Image.open(io.BytesIO(res.stdout))
    except Exception:
        return None


# ── Raster recoloring ───────────────────────────────────────────────────────
def recolor_raster_image(img, tone_map, palette):
    """Recolor a PIL image through `tone_map`, preserving alpha."""
    from PIL import Image
    out = np.array(img.convert("RGBA"), dtype=np.uint8)
    visible = out[..., 3] > 0
    if visible.any():
        tone, chroma = lab_tone_chroma(out[..., :3][visible])
        out_tone, weight = tone_map.apply(tone, chroma)
        out[..., :3][visible] = palette.sample(out_tone, weight)
    return Image.fromarray(out, "RGBA")


# ── SVG recoloring ──────────────────────────────────────────────────────────
_NAMED_COLORS = {
    "black": "#000000", "white": "#ffffff", "gray": "#808080", "grey": "#808080",
    "silver": "#c0c0c0", "red": "#ff0000", "green": "#008000", "blue": "#0000ff",
    "yellow": "#ffff00", "orange": "#ffa500", "purple": "#800080", "navy": "#000080",
    "teal": "#008080", "maroon": "#800000", "lime": "#00ff00", "aqua": "#00ffff",
    "cyan": "#00ffff", "magenta": "#ff00ff", "fuchsia": "#ff00ff", "olive": "#808000",
    "darkgray": "#a9a9a9", "darkgrey": "#a9a9a9", "lightgray": "#d3d3d3", "lightgrey": "#d3d3d3",
    "dimgray": "#696969", "dimgrey": "#696969", "whitesmoke": "#f5f5f5", "gainsboro": "#dcdcdc",
}

# A colour value after a paint property, in attributes and in CSS alike. Anchoring on the
# property keeps `href="#abc"` and `url(#bad)` id references out of reach.
_PAINT_RE = re.compile(
    r'(?P<prop>(?:stop-color|flood-color|lighting-color|solid-color|fill|stroke|color)\s*(?:=\s*["\']?|:\s*))'
    r'(?P<val>#[0-9a-fA-F]{8}\b|#[0-9a-fA-F]{6}\b|#[0-9a-fA-F]{3,4}\b|rgba?\([^)]*\)|[a-zA-Z]+\b)')
_RGB_FUNC_RE = re.compile(r'rgba?\(\s*([\d.]+%?)\s*[, ]\s*([\d.]+%?)\s*[, ]\s*([\d.]+%?)\s*(?:[,/]\s*([\d.]+%?)\s*)?\)')
# Masks are luminance, clip paths are geometry and filters are mostly shadows: their
# colours are not paint and recoloring them breaks the icon.
_SKIP_BLOCK_RE = re.compile(r'<(mask|clipPath|filter)\b.*?</\1\s*>', re.S)
_TAG_RE = re.compile(r'<[^>]+>')
_OPACITY_RE = re.compile(r'(?<![-\w])(?:fill-)?opacity\s*[:=]\s*["\']?\s*([\d.]+)')
_ROOT_SVG_RE = re.compile(r'<svg\b[^>]*>', re.S)

# Matches base64-embedded rasters in SVGs (quotes end the match: not in charset)
DATA_IMAGE_RE = re.compile(r'data:image/(?:png|jpe?g);base64,([A-Za-z0-9+/=\s]+)')


def _parse_color(value):
    """(r, g, b, alpha_suffix_or_None) for a CSS colour, None when not a colour."""
    v = value.strip()
    if v.startswith('#'):
        h = v[1:]
        alpha = None
        if len(h) == 4:
            h, alpha = h[:3], h[3] * 2
        elif len(h) == 8:
            h, alpha = h[:6], h[6:]
        if len(h) not in (3, 6):
            return None
        return _hex_to_rgb(h) + (alpha,)
    if v.lower().startswith('rgb'):
        m = _RGB_FUNC_RE.match(v)
        if not m:
            return None
        chans = []
        for part in m.groups()[:3]:
            chans.append(round(float(part[:-1]) * 2.55) if part.endswith('%') else round(float(part)))
        alpha = None
        if m.group(4):
            a = m.group(4)
            a = float(a[:-1]) / 100 if a.endswith('%') else float(a)
            alpha = "%02x" % max(0, min(255, round(a * 255)))
        return tuple(max(0, min(255, c)) for c in chans) + (alpha,)
    named = _NAMED_COLORS.get(v.lower())
    if named:
        return _hex_to_rgb(named) + (None,)
    return None


def _map_color(rgb, tone_map, palette, shadow=False):
    tone, chroma = lab_tone_chroma(np.array([rgb], dtype=np.float64))
    if shadow:
        # A translucent dark shape is a shadow: keep it dark even on a flipped icon
        out_tone, weight = np.minimum(tone, 12.0), np.array([0.3])
    else:
        out_tone, weight = tone_map.apply(tone, chroma)
    r, g, b = (int(v) for v in palette.sample(out_tone, weight)[0])
    return "#%02x%02x%02x" % (r, g, b)


def svg_tone_map(svg_bytes_or_path, content, contextual):
    """ToneMap for an SVG: measured on a render, else on its declared colours."""
    if not contextual:
        return ToneMap()
    img = render_svg(svg_bytes_or_path)
    if img is not None:
        return analyze_image(img)
    colors = [c for c in (_parse_color(m.group('val')) for m in _PAINT_RE.finditer(content)) if c]
    if not colors:
        return ToneMap("glyph", True, (0, 100), (ToneMap.GLYPH_TONE - 30, ToneMap.GLYPH_TONE + 15))
    tone, _ = lab_tone_chroma(np.array([c[:3] for c in colors], dtype=np.float64))
    return analyze_tones(tone, np.ones_like(tone), 0.5)


def recolor_svg(content, tone_map, palette, contextual=False):
    skip = [m.span() for m in _SKIP_BLOCK_RE.finditer(content)]
    tags = [m.span() for m in _TAG_RE.finditer(content)]
    tag_starts = [s for s, _ in tags]
    cache = {}

    def in_skip(pos):
        return any(s <= pos < e for s, e in skip)

    def is_translucent(pos):
        i = bisect.bisect_right(tag_starts, pos) - 1
        if i < 0 or not (tags[i][0] <= pos < tags[i][1]):
            return False
        for m in _OPACITY_RE.finditer(content, tags[i][0], tags[i][1]):
            try:
                if float(m.group(1)) < 0.4:
                    return True
            except ValueError:
                pass
        return False

    def replacer(match):
        parsed = _parse_color(match.group('val'))
        if parsed is None or in_skip(match.start()):
            return match.group(0)
        rgb, alpha = parsed[:3], parsed[3]
        shadow = (contextual and tone_map.invert and is_translucent(match.start())
                  and lab_tone_chroma(np.array(rgb, dtype=np.float64))[0] < 20)
        key = (rgb, shadow)
        if key not in cache:
            cache[key] = _map_color(rgb, tone_map, palette, shadow)
        return match.group('prop') + cache[key] + (alpha or "")

    new_content = _PAINT_RE.sub(replacer, content)

    # Shapes without a fill paint black by default, which no regex sees. Give the root a
    # fill so they take the palette too — unless a mask would inherit it.
    root = _ROOT_SVG_RE.search(new_content)
    if root and "<mask" not in new_content and not re.search(r'\sfill\s*=|fill\s*:', root.group(0)):
        default = _map_color((0, 0, 0), tone_map, palette)
        tag = root.group(0)
        tag = tag[:-2] + f' fill="{default}"/>' if tag.endswith('/>') else tag[:-1] + f' fill="{default}">'
        new_content = new_content[:root.start()] + tag + new_content[root.end():]

    if not new_content.lstrip().startswith("<?xml"):
        new_content = '<?xml version="1.0" encoding="UTF-8"?>\n' + new_content
    return new_content


def recolor_embedded_images(svg_content, palette, contextual):
    """Recolor base64-embedded rasters inside an SVG. macOS-style icon packs
    ship PNGs wrapped in SVG, which the colour text pass can't touch."""
    from PIL import Image

    def repl(match):
        try:
            img = Image.open(io.BytesIO(base64.b64decode(match.group(1), validate=False)))
            img.load()
            tone_map = analyze_image(img) if contextual else ToneMap()
            out = io.BytesIO()
            recolor_raster_image(img, tone_map, palette).save(out, "PNG")
            return "data:image/png;base64," + base64.b64encode(out.getvalue()).decode('ascii')
        except Exception:
            return match.group(0)

    return DATA_IMAGE_RE.sub(repl, svg_content)


def recolor_svg_file(source, palette, contextual):
    """Recolored SVG text for the file at `source`."""
    with open(source, 'r', errors='ignore') as f:
        content = f.read()
    # A wrapper around an embedded PNG (macOS-style packs) has no vector paint to map;
    # its image is measured on its own below, so skip rendering the whole thing.
    has_paint = any(_parse_color(m.group('val')) for m in _PAINT_RE.finditer(content))
    tone_map = svg_tone_map(source, content, contextual and has_paint)
    new_content = recolor_svg(content, tone_map, palette, contextual)
    if "base64," in new_content:
        new_content = recolor_embedded_images(new_content, palette, contextual)
    return new_content


def is_contextual(rel_path, filename):
    """App art gets per-icon normalisation; UI and symbolic glyphs keep their tones."""
    parts = rel_path.lower().replace("\\", "/").split("/")
    if "symbolic" in parts or "-symbolic" in filename.lower():
        return False
    return any(p.split("@")[0] in APP_CONTEXTS for p in parts)


def process_file(args):
    src_file, dst_file, palette, contextual = args
    try:
        if src_file.endswith(".svg"):
            new_content = recolor_svg_file(src_file, palette, contextual)
            with open(dst_file, 'w') as f:
                f.write(new_content)
        elif src_file.endswith(".png"):
            try:
                from PIL import Image
                img = Image.open(src_file)
                img.load()
                tone_map = analyze_image(img) if contextual else ToneMap()
                recolor_raster_image(img, tone_map, palette).save(dst_file, "PNG")
            except Exception:
                shutil.copy2(src_file, dst_file)
        else:
            shutil.copy2(src_file, dst_file)
        return True
    except Exception:
        return False


# ── Icon Scavenging (Phase 2) ───────────────────────────────────────────────
def get_icon_name_variations(icon_name):
    """
    Generate common variations of an icon name to improve lookup success.
    For example: 'zen' → ['zen', 'zen-browser', 'zen_browser', 'Zen', 'ZenBrowser']
    """
    variations = [icon_name]
    name_lower = icon_name.lower()
    if name_lower not in variations:
        variations.append(name_lower)

    # Try adding common suffixes for browsers/apps
    if not any(suffix in name_lower for suffix in ['-browser', '_browser', '-app', '_app']):
        variations += [name_lower + '-browser', name_lower + '_browser', name_lower + '-app', name_lower + '_app']

    # Try removing common suffixes
    for suffix in ['-browser', '_browser', '-app', '_app', '-icon', '_icon']:
        if name_lower.endswith(suffix):
            base = name_lower[:-len(suffix)]
            if base not in variations:
                variations.append(base)

    # Try different separators
    if '-' in icon_name:
        variations.append(icon_name.replace('-', '_'))
    if '_' in icon_name:
        variations.append(icon_name.replace('_', '-'))

    # Try camelCase/PascalCase variations
    if '-' in icon_name or '_' in icon_name:
        parts = re.split(r'[-_]', icon_name)
        pascal = ''.join(p.capitalize() for p in parts)
        variations += [pascal, pascal.lower()]

    # Reverse-domain ids: the last segment (dev.lizardbyte.app.Sunshine → sunshine)
    if name_lower.count('.') >= 2:
        variations.append(name_lower.rsplit('.', 1)[-1])

    return variations


_ICON_EXTS = (".svg", ".png", ".xpm")


def _size_rank(rel_dir):
    """Higher is better: scalable first, then the biggest fixed size."""
    rel = rel_dir.lower()
    if "scalable" in rel:
        return 100000
    m = re.search(r'(\d+)(?:x\d+)?', rel)
    return int(m.group(1)) if m else 0


def build_icon_index():
    """name.lower() → best source file, built once. App-owned locations (hicolor,
    pixmaps, loose files at the root of an icon dir) beat icons from other themes,
    which are a different style and only fill gaps."""
    own, themed = {}, {}

    def offer(index, name, path, rank):
        key = name.lower()
        if key not in index or rank > index[key][1]:
            index[key] = (path, rank)

    for icon_dir in ICON_SEARCH_DIRS:
        if not os.path.isdir(icon_dir):
            continue
        for entry in os.listdir(icon_dir):
            path = os.path.join(icon_dir, entry)
            if os.path.isfile(path) and entry.lower().endswith(_ICON_EXTS):
                # e.g. /usr/share/icons/awcc.png — not in any theme, but apps do it
                offer(own, os.path.splitext(entry)[0], path, 1)
                continue
            if not os.path.isdir(path) or entry in ("DynamicTheme", "DynamicTheme.new", "DynamicTheme.old"):
                continue
            index = own if entry == "hicolor" else themed
            for root, dirs, files in os.walk(path):
                rel = os.path.relpath(root, path)
                if "apps" not in rel.lower().split("/") and not rel.lower().startswith("apps"):
                    continue
                if "symbolic" in rel.lower():
                    continue
                rank = _size_rank(rel)
                for f in files:
                    if f.lower().endswith(_ICON_EXTS):
                        offer(index, os.path.splitext(f)[0], os.path.join(root, f), rank)

    for pixmap_dir in PIXMAP_DIRS:
        if not os.path.isdir(pixmap_dir):
            continue
        for f in os.listdir(pixmap_dir):
            path = os.path.join(pixmap_dir, f)
            if os.path.isfile(path):
                name = os.path.splitext(f)[0] if f.lower().endswith(_ICON_EXTS) else f
                offer(own, name, path, 2 if f.lower().endswith(".svg") else 1)

    return {k: v[0] for k, v in own.items()}, {k: v[0] for k, v in themed.items()}


_ICON_INDEX = None


def find_icon_in_themes(icon_name, theme_dirs=None):
    """Best source file for an icon name, trying common name variations."""
    global _ICON_INDEX
    if _ICON_INDEX is None:
        _ICON_INDEX = build_icon_index()
    own, themed = _ICON_INDEX
    variations = get_icon_name_variations(icon_name)
    for index in (own, themed):
        for variation in variations:
            hit = index.get(variation.lower())
            if hit:
                return hit
    return None


def sniff_image_kind(path):
    """'svg', 'raster' or None, by content — AppImage icons often have no extension."""
    try:
        with open(path, 'rb') as f:
            head = f.read(2048)
    except OSError:
        return None
    if head.startswith(b'\x1f\x8b'):
        return "svgz" if path.lower().endswith(".svgz") else None
    text = head.lstrip(b'\xef\xbb\xbf').lstrip().lower()
    if b'<svg' in text or (text.startswith(b'<?xml') and b'svg' in text):
        return "svg"
    if head.startswith(b'\x89PNG') or head[:3] == b'\xff\xd8\xff' or head.startswith(b'/* XPM */') \
            or head[:2] == b'BM' or head[:4] in (b'GIF8', b'RIFF'):
        return "raster"
    return None


def get_existing_tema_icons():
    """Get set of icon names (lowercase, no ext) already in DynamicTheme."""
    icons = set()
    for root, dirs, files in os.walk(TARGET_THEME_PATH):
        for f in files:
            icons.add(os.path.splitext(f)[0].lower())
    return icons


IMAGE_EXTENSIONS = {".png", ".svg", ".jpg", ".jpeg", ".xpm", ".gif", ".bmp"}


def strip_image_ext(name):
    """Strip image extension only. Preserves reverse-domain names like com.rtosta.zapzap."""
    _name, ext = os.path.splitext(name)
    if ext.lower() in IMAGE_EXTENSIONS:
        return _name
    return name  # keep as-is: com.rtosta.zapzap → com.rtosta.zapzap (not .zapzap stripped)


def scavenge_missing_icons(existing_icons):
    """
    Parse .desktop files, find icons not in DynamicTheme.
    Returns (svg, raster) lists of (icon_name, source_path) tuples.

    An absolute-path icon is injected under the .desktop file's own name. The .desktop is
    never rewritten to point at it: the shell maps the entry to that name only while themed
    icons are on, so turning them off leaves every app with its original icon.
    """
    missing_raster = []
    missing_svg = []
    queued = set()

    for desktop_dir in DESKTOP_SEARCH_DIRS:
        if not os.path.isdir(desktop_dir):
            continue
        for df in glob.glob(os.path.join(desktop_dir, "*.desktop")):
            try:
                cp = configparser.ConfigParser(interpolation=None, strict=False)
                cp.read(df, encoding='utf-8')
                if not cp.has_section('Desktop Entry'):
                    continue
                icon = cp.get('Desktop Entry', 'Icon', fallback='').strip()
                if not icon:
                    continue

                source_path = None
                if icon.startswith("/"):
                    # Absolute path — use .desktop filename as primary icon name
                    # e.g., zen.desktop with Icon=/path/to/default128.png → inject as "zen"
                    icon_basename = os.path.splitext(os.path.basename(df))[0]
                    file_basename = strip_image_ext(os.path.basename(icon))
                    if icon_basename.lower() in existing_icons and file_basename.lower() in existing_icons:
                        continue
                    if os.path.isfile(icon):
                        source_path = icon
                    else:
                        for ext in (".svg", ".png", ".xpm"):
                            if os.path.isfile(icon + ext):
                                source_path = icon + ext
                                break
                else:
                    # Icon name — use as-is (preserve full reverse-domain: com.rtosta.zapzap)
                    icon_basename = strip_image_ext(os.path.basename(icon))
                    if icon_basename.lower() in existing_icons:
                        continue
                    source_path = find_icon_in_themes(icon_basename)

                if not source_path:
                    continue

                names_to_inject = [icon_basename]
                if icon.startswith("/"):
                    file_basename = strip_image_ext(os.path.basename(icon))
                    if file_basename.lower() != icon_basename.lower() and file_basename.lower() not in existing_icons:
                        names_to_inject.append(file_basename)

                kind = sniff_image_kind(source_path)
                if kind is None and source_path.lower().endswith(".svg"):
                    kind = "svg"
                for inject_name in names_to_inject:
                    if inject_name.lower() in existing_icons or inject_name.lower() in queued:
                        continue
                    queued.add(inject_name.lower())
                    if kind == "svg":
                        missing_svg.append((inject_name, source_path))
                    elif kind != "svgz":
                        # Raster, or unknown (Pillow gets the last word)
                        missing_raster.append((inject_name, source_path))

            except Exception:
                continue

    return missing_svg, missing_raster


def _square(img):
    """Pad to a centred square so resizing never squashes the art."""
    from PIL import Image
    img = img.convert("RGBA")
    if img.width == img.height:
        return img
    side = max(img.width, img.height)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(img, ((side - img.width) // 2, (side - img.height) // 2))
    return canvas


def recolor_raster_icons(raster_icons, palette, target_apps_dir):
    try:
        from PIL import Image
    except ImportError:
        print("  Pillow not installed, skipping raster recoloring")
        return []

    successful_names = []
    for icon_name, source_path in raster_icons:
        try:
            src = Image.open(source_path)
            src.load()
            img = _square(src)
            img = recolor_raster_image(img, analyze_image(img), palette)

            for size in [256, 128, 64, 48, 32, 24, 16]:
                dest_dir = os.path.join(TARGET_THEME_PATH, f"{size}x{size}/apps")
                os.makedirs(dest_dir, exist_ok=True)
                img.resize((size, size), Image.Resampling.LANCZOS).save(
                    os.path.join(dest_dir, icon_name + ".png"), "PNG")

            # Wrap in an SVG and place in scalable/apps so Qt QIcon is guaranteed to pick it up
            scalable_dir = os.path.join(TARGET_THEME_PATH, "scalable/apps")
            os.makedirs(scalable_dir, exist_ok=True)
            out = io.BytesIO()
            img.resize((256, 256), Image.Resampling.LANCZOS).save(out, "PNG")
            b64_data = base64.b64encode(out.getvalue()).decode('ascii')
            with open(os.path.join(scalable_dir, icon_name + ".svg"), "w") as f:
                f.write(f"""<?xml version="1.0" encoding="UTF-8"?>
<svg viewBox="0 0 256 256" width="256" height="256" version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
  <image width="256" height="256" xlink:href="data:image/png;base64,{b64_data}"/>
</svg>""")

            successful_names.append(icon_name)
        except Exception as e:
            print(f"  Failed to process {icon_name}: {e}")

    return successful_names


def inject_scavenged_svgs(svg_icons, palette, target_apps_dir):
    """Recolor scavenged SVG icons and inject into DynamicTheme."""
    successful_names = []
    for icon_name, source_path in svg_icons:
        try:
            new_content = recolor_svg_file(source_path, palette, True)
            for size_dir in ["scalable/apps", "symbolic/apps"]:
                dest_dir = os.path.join(TARGET_THEME_PATH, size_dir)
                os.makedirs(dest_dir, exist_ok=True)
                with open(os.path.join(dest_dir, icon_name + ".svg"), 'w') as f:
                    f.write(new_content)
            successful_names.append(icon_name)
        except Exception as e:
            print(f"  Failed to process {icon_name}: {e}")
    return successful_names


def create_lowercase_symlinks(theme_path):
    """
    Scans the theme path and creates lowercase symlinks for all files containing
    uppercase characters. This ensures case-insensitive icon lookup succeeds on Linux.
    """
    print("Creating lowercase symlinks for case-insensitive icon lookup...")
    symlink_count = 0
    for root, dirs, files in os.walk(theme_path):
        for f in files:
            lower_f = f.lower()
            if lower_f != f:
                lower_path = os.path.join(root, lower_f)
                if not os.path.exists(lower_path):
                    try:
                        os.symlink(f, lower_path)
                        symlink_count += 1
                    except Exception:
                        pass
    print(f"  Created {symlink_count} lowercase symlinks.")


def get_theme_fingerprint(theme_path):
    """Cheap content fingerprint of a theme dir: file count + newest mtime.
    Directory mtimes are included because archive extraction preserves file
    mtimes but always touches the directories entries were written into."""
    count = 0
    newest = 0
    for root, dirs, files in os.walk(theme_path):
        count += len(files)
        for path in [root] + [os.path.join(root, f) for f in files]:
            try:
                mtime = int(os.lstat(path).st_mtime)
                if mtime > newest:
                    newest = mtime
            except OSError:
                pass
    return f"{count}:{newest}"


# ── Main Generation ─────────────────────────────────────────────────────────
def generate():
    # Rapid wallpaper switching spawns overlapping recolor processes that race
    # on the shared .new staging dir and on the final rename, so an older
    # palette can land after a newer one. Serialize runs with a lock and let
    # only the newest queued run do the work: each process stamps the pending
    # token; one that finds a newer stamp after acquiring the lock exits, and
    # the stamping run regenerates with the colors current at its turn.
    token = uuid.uuid4().hex
    token_path = TARGET_THEME_PATH + ".pending"
    try:
        with open(token_path, 'w') as f:
            f.write(token)
    except Exception:
        pass

    with open(TARGET_THEME_PATH + ".lock", 'w') as lock_file:
        fcntl.flock(lock_file, fcntl.LOCK_EX)
        try:
            with open(token_path) as f:
                if f.read().strip() != token:
                    print("A newer recolor run is queued; leaving the work to it.")
                    return
        except Exception:
            pass
        _generate_locked()


def _generate_locked():
    global TARGET_THEME_PATH
    config = get_config()
    colors = get_colors()

    if not colors:
        print("No colors found. Please check ~/.local/state/quickshell/user/generated/colors.json")
        return
    palette = Palette(colors)
    print(f"Palette keys (hue, chroma): {palette.fingerprint()}")

    # Get icon theme from config or default
    icon_theme_name = config.get("appearance", {}).get("iconTheme", "Papirus-Base")
    # A caller that just changed the config passes the base explicitly: the config write is
    # debounced, so reading it back from disk here would race with it.
    if "--base" in sys.argv:
        at = sys.argv.index("--base")
        if at + 1 < len(sys.argv):
            icon_theme_name = sys.argv[at + 1]
    print(f"Configured icon theme: {icon_theme_name}")

    # Locate base theme
    base_theme_path = ""
    for d in ICON_SEARCH_DIRS:
        p = os.path.join(d, icon_theme_name)
        if os.path.exists(p):
            base_theme_path = p
            break

    if not base_theme_path:
        print(f"Icon theme '{icon_theme_name}' not found. Falling back...")
        for fallback_name in ["Papirus-Base", "Papirus", "breeze", "Adwaita"]:
            for d in ICON_SEARCH_DIRS:
                p = os.path.join(d, fallback_name)
                if os.path.exists(p):
                    base_theme_path = p
                    icon_theme_name = fallback_name
                    break
            if base_theme_path: break

    if not base_theme_path:
        print("No suitable base theme found.")
        return

    print(f"Generating DynamicTheme using {icon_theme_name} as base from {base_theme_path}...")

    # ── Skip if colors, base theme name AND base theme content unchanged ──
    # The content fingerprint catches the base theme being updated/reinstalled
    # in place (same name, different files), which the name tag alone misses.
    # Only hue and chroma reach the icons, so toggling light/dark (same palettes) skips.
    colors_hash = hashlib.md5(json.dumps([ALGORITHM_VERSION, palette.fingerprint()],
                                         sort_keys=True).encode()).hexdigest()
    hash_file = TARGET_THEME_PATH + ".colhash"
    base_fingerprint = get_theme_fingerprint(base_theme_path)
    fp_file = TARGET_THEME_PATH + ".basefp"
    if not FORCE:
        try:
            if os.path.isfile(hash_file) and open(hash_file).read().strip() == colors_hash and os.path.isdir(TARGET_THEME_PATH):
                base_tag = TARGET_THEME_PATH + ".basetheme"
                if os.path.isfile(base_tag) and open(base_tag).read().strip() == icon_theme_name:
                    if os.path.isfile(fp_file) and open(fp_file).read().strip() == base_fingerprint:
                        print(f"Colors and base theme unchanged (hash={colors_hash[:8]}), skipping regeneration.")
                        return
        except Exception:
            pass

    # ── Phase 0: Generate into temp dir, then atomic swap ─────────────────
    # We generate into TARGET_THEME_PATH + ".new" and rename at the end
    # so Quickshell always has a complete set of icons available.
    NEW_THEME_PATH = TARGET_THEME_PATH + ".new"
    if os.path.exists(NEW_THEME_PATH):
        shutil.rmtree(NEW_THEME_PATH)
    os.makedirs(NEW_THEME_PATH, exist_ok=True)

    # Patch all TARGET_THEME_PATH references below to point to NEW_THEME_PATH during generation
    # We do this by temporarily swapping the global
    OLD_TARGET = TARGET_THEME_PATH
    TARGET_THEME_PATH = NEW_THEME_PATH

    # Create index.theme
    src_index = os.path.join(base_theme_path, "index.theme")
    dst_index = os.path.join(TARGET_THEME_PATH, "index.theme")

    if os.path.exists(src_index):
        with open(src_index, 'r') as f:
            lines = f.readlines()

        with open(dst_index, 'w') as f:
            for line in lines:
                if line.startswith("Name="):
                    f.write("Name=DynamicTheme\n")
                elif line.startswith("Inherits="):
                    f.write(f"Inherits={icon_theme_name},hicolor\n")
                elif line.startswith("Comment="):
                    f.write(f"Comment=Dynamic Material You icons from {icon_theme_name}\n")
                elif line.startswith("KDE-Extensions="):
                    # KIconLoader only probes the listed extensions. SVG-only themes
                    # ship this as ".svg", which would hide every PNG we generate
                    # (recolored base rasters, scavenged icons) from KDE/Qt apps.
                    pass
                else:
                    f.write(line)
    else:
        with open(dst_index, "w") as f:
            f.write(f"[Icon Theme]\nName=DynamicTheme\nInherits={icon_theme_name},hicolor\n"
                    f"Directories=scalable/apps,symbolic/apps,256x256/apps,128x128/apps,48x48/apps\n\n"
                    f"[scalable/apps]\nSize=256\nMinSize=16\nMaxSize=1024\nType=Scalable\nContext=Applications\n\n"
                    f"[symbolic/apps]\nSize=16\nMinSize=8\nMaxSize=512\nType=Scalable\nContext=Applications\n\n"
                    f"[256x256/apps]\nSize=256\nType=Fixed\nContext=Applications\n\n"
                    f"[128x128/apps]\nSize=128\nType=Fixed\nContext=Applications\n\n"
                    f"[48x48/apps]\nSize=48\nType=Fixed\nContext=Applications\n")

    # ── Phase 1: Recolor base theme icons (vector, raster, base64-in-SVG) ─
    # Symlinks are recreated, not expanded: a pack aliases thousands of names onto a few
    # thousand drawings, and whole size folders (apps@2x -> apps) onto each other.
    tasks = []
    links = []
    processed_folders = set()
    base_real = os.path.realpath(base_theme_path)

    def in_context(rel):
        return any(part.split("@")[0].lower() in RECOLOR_CONTEXTS for part in rel.split(os.sep))

    def internal_target(link_path):
        """The link's target relative to the theme root when it stays inside a
        recolored folder, else None (then it is processed as a plain file)."""
        real = os.path.realpath(link_path)
        if not os.path.exists(real) or not real.startswith(base_real + os.sep):
            return None
        rel = os.path.relpath(real, base_real)
        return rel if in_context(rel) else None

    for root_dir, dirs, files in os.walk(base_theme_path):
        rel_path = os.path.relpath(root_dir, base_theme_path)
        for d in dirs:
            src = os.path.join(root_dir, d)
            if os.path.islink(src):
                rel_d = os.path.normpath(os.path.join(rel_path, d))
                target = internal_target(src)
                if target and in_context(rel_d):
                    links.append((rel_d, target))
        if rel_path == "." or not in_context(rel_path):
            continue
        dst_folder = os.path.join(TARGET_THEME_PATH, rel_path)
        os.makedirs(dst_folder, exist_ok=True)
        processed_folders.add(rel_path)
        contextual = is_contextual(rel_path, "")

        for filename in files:
            if not (filename.endswith(".svg") or filename.endswith(".png")):
                continue
            src = os.path.join(root_dir, filename)
            if os.path.islink(src):
                target = internal_target(src)
                if target:
                    links.append((os.path.join(rel_path, filename), target))
                    continue
                if not os.path.exists(src):
                    continue
            tasks.append((src, os.path.join(dst_folder, filename), palette,
                          contextual and is_contextual(rel_path, filename)))

    print(f"[Phase 1] Processing {len(tasks)} base theme icons from {len(processed_folders)} folders...")

    # Processes, not threads: the per-icon work is mostly Python and NumPy on small arrays,
    # which threads serialise on the GIL.
    with ProcessPoolExecutor(max_workers=os.cpu_count() or 8) as executor:
        results = list(executor.map(process_file, tasks, chunksize=64))

    link_count = 0
    for rel_link, rel_target in links:
        dst = os.path.join(TARGET_THEME_PATH, rel_link)
        try:
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            if os.path.lexists(dst):
                continue
            os.symlink(os.path.relpath(os.path.join(TARGET_THEME_PATH, rel_target), os.path.dirname(dst)), dst)
            link_count += 1
        except OSError:
            pass
    print(f"  Recreated {link_count} symlinks.")

    base_count = sum(1 for r in results if r)
    print(f"[Phase 1] Done! {base_count} base icons recolored.")

    # ── Phase 2: Scavenge & recolor missing icons ────────────────────────
    print("[Phase 2] Scavenging missing icons from .desktop files...")
    existing = get_existing_tema_icons()
    missing_svg, missing_raster = scavenge_missing_icons(existing)
    print(f"  Found {len(missing_svg)} SVG + {len(missing_raster)} raster icons to scavenge")

    svg_count = 0
    raster_count = 0

    # 2a: SVGs — direct recolor
    if missing_svg:
        successful_svgs = inject_scavenged_svgs(missing_svg, palette, TARGET_THEME_PATH)
        svg_count = len(successful_svgs)
        print(f"  Injected {svg_count} scavenged SVG icons")

    # 2b: Raster — Pillow pixel-perfect brightness mapping recolor
    if missing_raster:
        successful_rasters = recolor_raster_icons(missing_raster, palette, TARGET_THEME_PATH)
        raster_count = len(successful_rasters)
        print(f"  Injected {raster_count} Pillow-recolored raster icons")

    # ── Phase 3: Finalize ────────────────────────────────────────────────
    # Create lowercase symlinks for case-insensitive lookup
    create_lowercase_symlinks(TARGET_THEME_PATH)

    # Update index.theme Directories if needed (ensure scavenged dirs are listed)
    _ensure_directories_in_index(dst_index)

    # ── Atomic swap: replace old DynamicTheme with new one ───────────────
    # Restores TARGET_THEME_PATH global to original value before swapping
    TARGET_THEME_PATH = OLD_TARGET
    # The caches are built on the staging copy, before the swap: rewriting them inside the
    # live directory hands a half-written cache to anything resolving icons at that moment,
    # which crashes it (bad_alloc in KIconTheme) rather than just missing.
    print("[Phase 3] Updating GTK3 and GTK4 icon caches...")
    if shutil.which("gtk4-update-icon-cache"):
        subprocess.run(["gtk4-update-icon-cache", "-f", "-q", "-t", NEW_THEME_PATH], capture_output=True)
    if shutil.which("gtk-update-icon-cache"):
        subprocess.run(["gtk-update-icon-cache", "-f", "-q", "-t", NEW_THEME_PATH], capture_output=True)

    OLD_PATH = TARGET_THEME_PATH + ".old"
    if os.path.exists(TARGET_THEME_PATH):
        if os.path.exists(OLD_PATH):
            shutil.rmtree(OLD_PATH)
        os.rename(TARGET_THEME_PATH, OLD_PATH)
    os.rename(NEW_THEME_PATH, TARGET_THEME_PATH)
    if os.path.exists(OLD_PATH):
        shutil.rmtree(OLD_PATH)

    # Point every copy of the icon theme setting at DynamicTheme and tell running apps to
    # re-read it. This used to set gsettings alone, which left kdeglobals naming whatever pack
    # was picked before themed icons were turned on - and since that is the copy Qt reads, the
    # first refresh after a wallpaper change dropped the whole desktop back onto that old pack,
    # uncoloured. The same script does this for the pack picker, so the two cannot drift.
    #
    # It also has to run before the hash file below: the shell watches that file and redraws
    # every icon on screen when it changes, and a redraw that happens before the loader has
    # been pointed at the new theme draws the old one.
    subprocess.run(["bash", os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                         "apply_icon_theme.sh"), "DynamicTheme"],
                   capture_output=True)

    # Save hash + base theme fingerprint so next run can skip if nothing changed
    try:
        with open(hash_file, 'w') as f:
            f.write(colors_hash)
        base_tag = TARGET_THEME_PATH + ".basetheme"
        with open(base_tag, 'w') as f:
            f.write(icon_theme_name)
        with open(fp_file, 'w') as f:
            f.write(base_fingerprint)
    except Exception:
        pass

    total = base_count + svg_count + raster_count
    print(f"Generation complete. {total} total icons in DynamicTheme.")


def _ensure_directories_in_index(index_path):
    """Make sure all actual subdirs are listed in index.theme Directories."""
    if not os.path.isfile(index_path):
        return

    actual_dirs = set()
    for root, dirs, files in os.walk(TARGET_THEME_PATH):
        if files:
            rel = os.path.relpath(root, TARGET_THEME_PATH)
            if rel != ".":
                actual_dirs.add(rel)

    with open(index_path, 'r') as f:
        content = f.read()

    # Find existing Directories= line
    match = re.search(r'^Directories=(.*)$', content, re.MULTILINE)
    if match:
        existing = set(d.strip() for d in match.group(1).split(',') if d.strip())
        merged = existing | actual_dirs
        new_line = "Directories=" + ",".join(sorted(merged))
        content = content[:match.start()] + new_line + content[match.end():]

        # Add missing section headers for new directories
        for d in actual_dirs - existing:
            parts = d.split('/')
            context = "Applications" if "apps" in d.lower() else (
                "MimeTypes" if "mime" in d.lower() else
                "Places" if "places" in d.lower() else
                "Devices" if "devices" in d.lower() else
                "Actions" if "actions" in d.lower() else
                "Status" if "status" in d.lower() else
                "Categories"
            )
            # Determine if scalable or fixed
            if "scalable" in d.lower() or "symbolic" in d.lower():
                section = (f"\n\n[{d}]\nSize=256\nMinSize=16\nMaxSize=1024\n"
                          f"Type=Scalable\nContext={context}\n")
            else:
                # Try to extract size from dir name
                size_match = re.search(r'(\d+)x\d+', d)
                size = size_match.group(1) if size_match else "48"
                section = f"\n\n[{d}]\nSize={size}\nType=Fixed\nContext={context}\n"

            content += section

        with open(index_path, 'w') as f:
            f.write(content)


if __name__ == "__main__":
    generate()
