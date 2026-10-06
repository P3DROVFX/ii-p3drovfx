#!/usr/bin/env python3
"""Behaviour tests for scripts/colors/recolor_icons.py: tone normalisation and icon lookup."""

import importlib.util
import os
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
_argv = sys.argv
sys.argv = [_argv[0]]
_spec = importlib.util.spec_from_file_location("recolor_icons", ROOT / "scripts/colors/recolor_icons.py")
recolor = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(recolor)
sys.argv = _argv

TONAL_SPOT = {"primary": "#ffb77c", "primary_container": "#6c3a0c", "on_primary_container": "#ffdcc2",
              "secondary": "#e4bfa7", "secondary_container": "#5b4130"}
INTENSE = {"primary": "#b4c5ff", "primary_container": "#0040e0", "on_primary_container": "#dce1ff",
           "secondary": "#b9c3ff", "secondary_container": "#2a3fb0"}


def plate_icon(plate, logo, size=64):
    """A rounded-square plate with a centred logo, as a PIL image."""
    from PIL import Image, ImageDraw
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((4, 4, size - 5, size - 5), radius=14, fill=plate)
    d.ellipse((22, 22, size - 23, size - 23), fill=logo)
    return img


def tone_at(img, xy):
    return float(recolor.lab_tone_chroma(np.array([img.getpixel(xy)[:3]], dtype=np.uint8))[0][0])


class RecolorToneTests(unittest.TestCase):
    def setUp(self):
        self.palette = recolor.Palette(TONAL_SPOT)

    def recolored(self, img):
        return recolor.recolor_raster_image(img, recolor.analyze_image(img), self.palette)

    def test_light_and_dark_plates_land_on_the_same_tones(self):
        light = self.recolored(plate_icon((250, 250, 250, 255), (30, 90, 200, 255)))
        dark = self.recolored(plate_icon((20, 20, 24, 255), (120, 200, 255, 255)))
        for img in (light, dark):
            self.assertAlmostEqual(tone_at(img, (8, 32)), recolor.ToneMap.PLATE_TONE, delta=3)
            self.assertGreater(tone_at(img, (32, 32)), 70)

    def test_bare_glyph_comes_out_light(self):
        from PIL import Image, ImageDraw
        img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        ImageDraw.Draw(img).ellipse((24, 24, 40, 40), fill=(10, 10, 10, 255))
        out = self.recolored(img)
        self.assertGreater(tone_at(out, (32, 32)), 70)
        self.assertEqual(out.getpixel((2, 2))[3], 0)

    def test_ui_glyphs_keep_their_tone(self):
        svg = '<svg xmlns="http://www.w3.org/2000/svg"><path fill="#363636" d="M0 0h4v4z"/></svg>'
        out = recolor.recolor_svg(svg, recolor.ToneMap(), self.palette)
        hexval = out.split('<path fill="')[1][:7]
        rgb = np.array([[int(hexval[i:i + 2], 16) for i in (1, 3, 5)]], dtype=np.uint8)
        self.assertAlmostEqual(float(recolor.lab_tone_chroma(rgb)[0][0]), 22.6, delta=2)

    def test_intense_scheme_gives_more_chroma(self):
        tone = np.array([30.0])
        calm = self.palette.sample(tone, np.array([1.0]))[0].astype(np.uint8)
        vivid = recolor.Palette(INTENSE).sample(tone, np.array([1.0]))[0].astype(np.uint8)
        c = lambda rgb: float(recolor.lab_tone_chroma(np.array([rgb]))[1][0])
        self.assertGreater(c(vivid), c(calm))

    def test_svg_references_masks_and_alpha_survive(self):
        svg = ('<svg xmlns="http://www.w3.org/2000/svg"><defs><mask id="m"><rect fill="#ffffff"/></mask></defs>'
               '<use href="#abc"/><path fill="url(#bad)" stroke="#11223380" mask="url(#m)"/></svg>')
        out = recolor.recolor_svg(svg, recolor.ToneMap(), self.palette)
        self.assertIn('href="#abc"', out)
        self.assertIn('url(#bad)', out)
        self.assertIn('<rect fill="#ffffff"/>', out)
        self.assertRegex(out, r'stroke="#[0-9a-f]{6}80"')


class IconLookupTests(unittest.TestCase):
    def test_extensionless_svg_is_sniffed_as_svg(self):
        with tempfile.NamedTemporaryFile("w", delete=False) as f:
            f.write('<?xml version="1.0"?>\n<!DOCTYPE svg>\n<svg xmlns="http://www.w3.org/2000/svg"/>')
        try:
            self.assertEqual(recolor.sniff_image_kind(f.name), "svg")
        finally:
            os.unlink(f.name)

    def test_loose_file_at_icon_dir_root_is_found(self):
        with tempfile.TemporaryDirectory() as icons:
            Path(icons, "awcc.png").write_bytes(b"\x89PNG\r\n\x1a\n")
            saved = (recolor.ICON_SEARCH_DIRS, recolor.PIXMAP_DIRS, recolor._ICON_INDEX)
            recolor.ICON_SEARCH_DIRS, recolor.PIXMAP_DIRS, recolor._ICON_INDEX = [icons], [], None
            try:
                self.assertEqual(recolor.find_icon_in_themes("awcc"), os.path.join(icons, "awcc.png"))
            finally:
                recolor.ICON_SEARCH_DIRS, recolor.PIXMAP_DIRS, recolor._ICON_INDEX = saved


if __name__ == "__main__":
    unittest.main()
