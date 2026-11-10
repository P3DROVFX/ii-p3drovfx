"""Contracts for the dock utility widgets (modules/ii/dock/utilities)."""

from pathlib import Path
import json
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
UTIL = ROOT / "modules/ii/dock/utilities"
SETTINGS = ROOT / "modules/settings/configs/dockUtilities"
CATALOG = (UTIL / "DockUtilityCatalog.js").read_text()
DOCK_CONTENT = (ROOT / "modules/ii/dock/DockContent.qml").read_text()
EN = json.loads((ROOT / "translations/en_US.json").read_text())
PT = json.loads((ROOT / "translations/pt_BR.json").read_text())


def catalog_kinds():
    body = CATALOG.split("var kinds = [", 1)[1].split("];", 1)[0]
    kinds = []
    for block in re.findall(r"\{(.*?)\}", body, re.S):
        fields = dict(re.findall(r'(\w+):\s*"([^"]*)"', block))
        flags = dict(re.findall(r"(\w+):\s*(true|false)", block))
        fields.update({k: v == "true" for k, v in flags.items()})
        kinds.append(fields)
    return kinds


def qmldir_types(folder):
    text = (folder / "qmldir").read_text()
    return set(re.findall(r"^(\w+) 1\.0 \w+\.qml$", text, re.M))


class DockUtilityWidgetsContractTests(unittest.TestCase):
    def test_catalog_parses(self):
        self.assertGreater(len(catalog_kinds()), 0)

    def test_every_kind_has_its_files(self):
        for kind in catalog_kinds():
            name = kind["file"]
            self.assertTrue((UTIL / f"{name}Tile.qml").exists(), name)
            if kind.get("panel"):
                self.assertTrue((UTIL / f"{name}Panel.qml").exists(), name)
            if kind.get("settings"):
                self.assertTrue((SETTINGS / f"{name}Config.qml").exists(), name)

    def test_qmldir_lists_every_type(self):
        # Tiles load by URL: without a qmldir entry their base type is
        # "not a type" (the scanner never sees the folder).
        types = qmldir_types(UTIL)
        for path in UTIL.glob("*.qml"):
            self.assertIn(path.stem, types, path.name)
        settings_types = qmldir_types(SETTINGS)
        for name in ("DockUtilityCard", "UtilityConfigPage"):
            self.assertIn(name, settings_types)

    def test_tiles_extend_the_base(self):
        for kind in catalog_kinds():
            text = (UTIL / f"{kind['file']}Tile.qml").read_text()
            self.assertRegex(text, re.compile(r"^UtilityTile \{", re.M), kind["file"])

    def test_tiles_stay_sharp_under_the_lens(self):
        # The lens scales tiles up: natively rasterised glyphs and Canvas
        # shapes painted at base size turn to pixels. Tiles use the Tile*
        # components (curve-rendered text, oversized shapes) instead.
        forbidden = re.compile(r"^\s*(MaterialSymbol|StyledText|MaterialShape|MaterialShapeWrappedMaterialSymbol|ClockCardAction|ClockPlayButton)\s*\{", re.M)
        for kind in catalog_kinds():
            text = (UTIL / f"{kind['file']}Tile.qml").read_text()
            self.assertIsNone(forbidden.search(text), kind["file"])

    def test_no_borders_on_tiles_or_cards(self):
        files = [UTIL / f"{k['file']}Tile.qml" for k in catalog_kinds()]
        files.append(SETTINGS / "DockUtilityCard.qml")
        for path in files:
            self.assertNotIn("border.width", path.read_text(), path.name)

    def test_titles_are_translated(self):
        for kind in catalog_kinds():
            for key in (kind["title"], kind["description"]):
                self.assertIn(key, EN, key)
                self.assertIn(key, PT, key)

    def test_dock_content_knows_the_type(self):
        self.assertIn('case "utility":\n                        return utilityItemComponent;', DOCK_CONTENT)
        self.assertIn("root._utilitySlots(item)", DOCK_CONTENT)
        self.assertIn("_magnificationProfileForItem(root.flattenedItems[i])", DOCK_CONTENT)

    def test_local_preferences_protect_the_list(self):
        prefs = (ROOT / "modules/common/LocalPreferences.qml").read_text()
        self.assertIn('"dock.utilityWidgets"', prefs)
        helper = (ROOT / "scripts/presets_helper.py").read_text()
        self.assertIn('"utilityWidgets"', helper)


if __name__ == "__main__":
    unittest.main()
