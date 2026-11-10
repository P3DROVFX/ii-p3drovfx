#!/usr/bin/env python3
"""Settings search landmarks: headings the redesigned pages draw outside cloneable controls."""

import json
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "settings"))

import search_landmarks as L  # noqa: E402


def registry_pages():
    src = (ROOT / "modules/common/SettingsPageRegistry.qml").read_text(encoding="utf-8")
    literal = src.split("readonly property var pages:", 1)[1].split("\n    ]\n", 1)[0] + "]"
    literal = re.sub(r"^\s*//.*$", "", literal, flags=re.M)
    literal = re.sub(r",(\s*[\]}])", r"\1", literal)
    return json.loads(literal)


class Extraction(unittest.TestCase):
    def test_bound_short_strings_only(self):
        text = (
            'Item { text: Translation.tr("Color scheme") // "x\n'
            ' tooltip: Translation.tr("Nope")\n'
            ' label: c ? Translation.tr("Alpha beta") : Translation.tr("Gamma delta")\n'
            ' x: Translation.tr("%1 items").arg(n)\n'
            ' y: Translation.tr("Dark mode").arg(1)\n'
            ' z: Translation.tr("Checking…")\n'
            ' function f() { return Translation.tr("Computed label") }\n'
            ' w: Translation.tr("A whole sentence describing a thing.") }')
        self.assertEqual(L.extract_landmarks(text), ["Color scheme", "Alpha beta", "Gamma delta"])

    def test_model_literals(self):
        text = 'model: [{ label: Translation.tr("Built-in"), value: 1 }, { description: Translation.tr("Skip me") }]'
        self.assertEqual(L.extract_landmarks(text), ["Built-in"])

    def test_types_ignore_strings_and_comments(self):
        text = 'ColumnLayout { ColorsPalettePane { text: "Fake {" } // Commented {\n Loader { sourceComponent: Foo{} } }'
        self.assertEqual(L.referenced_types(text), ["ColumnLayout", "ColorsPalettePane", "Loader", "Foo"])

    def test_import_dirs(self):
        text = 'import qs.modules.settings.configs.colors\nimport "../widgets"\nimport "x.js" as X'
        self.assertEqual(L.import_dirs(text, "/r/modules/settings/configs/A.qml", "/r/"),
                         ["/r/modules/settings/configs/", "/r/modules/settings/configs/colors/", "/r/modules/settings/widgets/"])

    def test_sub_page_titles(self):
        text = 'ConfigSubpageRow { title: Translation.tr("OpenRGB"); configPage: Qt.resolvedUrl("widgets/OpenRGBConfig.qml") }'
        self.assertEqual(L.sub_page_titles(text, "/r/c/Page.qml"), {"/r/c/widgets/OpenRGBConfig.qml": "OpenRGB"})
        self.assertEqual(L.fallback_title("widgets/WallpaperEngineConfig.qml"), "Wallpaper Engine")


class RealPages(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pages = registry_pages()
        cls.blocks = {}
        cls.landmarks = L.crawl(str(ROOT) + "/", [p for p in cls.pages if p.get("searchable") is not False], cls.blocks)

    def block_of(self, page_id, key, sub_page=""):
        lm = next(l for l in self.landmarks if l["pageId"] == page_id and l["key"] == key and l["subPage"] == sub_page)
        return self.blocks.get(lm.get("block", ""))

    def has(self, page_id, key, sub_page=""):
        return any(l["pageId"] == page_id and l["key"] == key and l["subPage"] == sub_page for l in self.landmarks)

    def test_colors_page_headings(self):
        for key in ("Color scheme", "Wallpaper colors", "Themes", "Custom", "Customize", "Change wallpaper",
                    "Light mode", "Automation & integrations", "App theming", "Wallpaper Engine", "OpenRGB integration"):
            self.assertTrue(self.has("colors", key), key)

    def test_sub_page_landmarks_open_the_sub_page(self):
        self.assertTrue(self.has("colors", "Installed Wallpapers", "widgets/WallpaperEngineConfig.qml"))

    def test_no_prose_or_templates(self):
        for l in self.landmarks:
            self.assertNotRegex(l["key"], r"%\d")
            self.assertLessEqual(len(l["key"]), L.MAX_CHARS)
            self.assertFalse(l["key"].endswith((".", "…")), l["key"])
        self.assertFalse(self.has("colors", "From your wallpaper"))

    def test_components_drawing_landmarks_are_cloneable(self):
        self.assertEqual(self.block_of("colors", "Color scheme")["type"], "ColorsPalettePane")
        self.assertEqual(self.block_of("colors", "Change wallpaper")["type"], "ColorsWallpaperHero")
        tile = self.block_of("colors", "Wallpaper Engine")
        self.assertEqual(tile["type"], "ColorsFeatureTile")
        # Sibling geometry: the literal height is inlined, the computed width dropped.
        self.assertIn("height: 200", tile["source"])
        self.assertNotIn("tiles.", tile["source"])
        self.assertIn("Layout.fillWidth: true", tile["source"])
        # `colorsThemesRoot.activeSubPage = …` gets a stand-in that opens the sub-page.
        self.assertEqual(tile["rootId"], "colorsThemesRoot")
        self.assertTrue(tile["source"].startswith("ColorsFeatureTile {") and tile["source"].endswith("}"))

    def test_uncloneable_components_stay_links(self):
        # A Repeater delegate reads modelData; an overlay anchors over the page.
        types = {b["type"] for b in self.blocks.values()}
        self.assertNotIn("BackgroundModelRow", types)
        self.assertNotIn("FingerprintEnrollOverlay", types)
        # Headings on the page itself, outside any settings component.
        self.assertIsNone(self.block_of("colors", "Automation & integrations"))

    def test_presentable_rules(self):
        files = {"/r/modules/settings/configs/Tile.qml"}
        text = (
            "import QtQuick\nItem {\n    id: page\n"
            "    Item {\n        id: grid\n        readonly property int cellHeight: 120\n        property int cellWidth: page.width / 3\n"
            "        Tile {\n            width: grid.cellWidth\n            height: grid.cellHeight\n"
            "            onOpen: page.activeSubPage = \"x.qml\"\n        }\n"
            "        Tile {\n            text: grid.label\n        }\n"
            "        Repeater { Tile { title: modelData.name } }\n    }\n}\n")
        root = L.RootFile("/r/modules/settings/configs/Page.qml", text, "/r/", files)
        tiles = [b for b in root.blocks if b[0] == "Tile"]
        ok = L.presentable_block(root, tiles[0], lambda p: "", "/r/", files, {})
        self.assertIn("height: 120", ok["source"])
        self.assertNotIn("cellWidth", ok["source"])
        self.assertEqual(ok["rootId"], "page")
        self.assertIsNone(L.presentable_block(root, tiles[1], lambda p: "", "/r/", files, {}), "outside id in a binding")
        self.assertIsNone(L.presentable_block(root, tiles[2], lambda p: "", "/r/", files, {}), "delegate")

    def test_every_page_with_its_own_file_has_landmarks(self):
        ids = {l["pageId"] for l in self.landmarks}
        # Network draws only tabs whose sections are indexed through searchSources.
        missing = [p["id"] for p in self.pages if p.get("searchable") is not False and p["id"] not in ids and p["id"] != "network"]
        self.assertEqual(missing, [])


if __name__ == "__main__":
    unittest.main()
