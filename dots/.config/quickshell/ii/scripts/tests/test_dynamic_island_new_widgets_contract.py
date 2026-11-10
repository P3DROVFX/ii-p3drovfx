import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
CATALOG_PATH = ROOT / "modules/common/quickToggles/androidStyle/QuickToggleCatalog.js"
CHOOSER_PATH = ROOT / "modules/common/quickToggles/androidStyle/AndroidToggleDelegateChooser.qml"
TRAY_PREVIEW_PATH = ROOT / "modules/common/quickToggles/androidStyle/QuickToggleTrayPreview.qml"

SPORTS_TOGGLE_PATH = ROOT / "modules/common/quickToggles/androidStyle/sports/AndroidSportsToggle.qml"
SPORTS_CARD_PATH = ROOT / "modules/common/quickToggles/androidStyle/sports/AndroidSportsCardToggle.qml"
PHOTO_TOGGLE_PATH = ROOT / "modules/common/quickToggles/androidStyle/AndroidPhotoWidgetToggle.qml"


class DynamicIslandNewWidgetsContractTest(unittest.TestCase):
    def test_sysmon_removed(self):
        catalog_text = CATALOG_PATH.read_text(encoding="utf-8")
        sysmon_variants = ["sysmonExpressive", "sysmonCpuExpressive", "sysmonRamExpressive"]
        for v in sysmon_variants:
            self.assertNotIn(f"{v}:", catalog_text, f"{v} should be removed from catalog")

        tray_text = TRAY_PREVIEW_PATH.read_text(encoding="utf-8")
        for v in sysmon_variants:
            self.assertNotIn(f"{v}:", tray_text, f"{v} should be removed from tray preview")

        chooser_text = CHOOSER_PATH.read_text(encoding="utf-8")
        self.assertNotIn("qs.modules.common.quickToggles.androidStyle.sysmon", chooser_text)
        for v in sysmon_variants:
            self.assertNotIn(f'roleValue: "{v}"', chooser_text)

    def test_catalog_sports_widgets(self):
        catalog_text = CATALOG_PATH.read_text(encoding="utf-8")
        sports_variants = ["sportsWidget", "sportsCard"]
        for v in sports_variants:
            self.assertIn(f"{v}: {{", catalog_text, f"{v} missing in catalog")
            self.assertIn('variantGroup: "sports"', catalog_text)
            v_def = catalog_text.split(f"{v}: {{")[1].split("}")[0]
            self.assertIn('"island"', v_def, f"{v} should have island family")

    def test_catalog_photo_widget(self):
        catalog_text = CATALOG_PATH.read_text(encoding="utf-8")
        self.assertIn("photoWidget: {", catalog_text)
        photo_def = catalog_text.split("photoWidget: {")[1].split("}")[0]
        self.assertIn('"island"', photo_def)
        self.assertIn("maxHeight: 8", photo_def)
        self.assertNotIn("allowedSizes", photo_def, "photoWidget should be totally freeform")

    def test_tray_preview_metadata(self):
        tray_text = TRAY_PREVIEW_PATH.read_text(encoding="utf-8")
        all_widgets = ["sportsWidget", "sportsCard", "photoWidget"]
        for w in all_widgets:
            self.assertIn(f"{w}: {{", tray_text, f"{w} missing in tray preview meta")

    def test_chooser_contains_all_delegates(self):
        chooser_text = CHOOSER_PATH.read_text(encoding="utf-8")
        self.assertIn("qs.modules.common.quickToggles.androidStyle.sports", chooser_text)

        expected = [
            ("sportsWidget", "AndroidSportsToggle"),
            ("sportsCard", "AndroidSportsCardToggle"),
            ("photoWidget", "AndroidPhotoWidgetToggle"),
        ]
        for role, component in expected:
            self.assertIn(f'roleValue: "{role}"', chooser_text)
            self.assertIn(f"{component} {{", chooser_text)

    def test_files_exist_and_conform(self):
        self.assertTrue(SPORTS_TOGGLE_PATH.exists())
        self.assertTrue(SPORTS_CARD_PATH.exists())
        self.assertTrue(PHOTO_TOGGLE_PATH.exists())

        # Sports Toggle
        sports_text = SPORTS_TOGGLE_PATH.read_text(encoding="utf-8")
        self.assertIn("SportsService", sports_text)
        self.assertIn("nextGame", sports_text)

        # Photo Widget
        photo_text = PHOTO_TOGGLE_PATH.read_text(encoding="utf-8")
        self.assertIn("PreserveAspectCrop", photo_text)
        self.assertIn("WidgetPhotoPicker", photo_text)
        self.assertIn("!root.editMode", photo_text)


if __name__ == "__main__":
    unittest.main()
