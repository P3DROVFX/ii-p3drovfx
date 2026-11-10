from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]


class ScreenCornersLifecycleContractTest(unittest.TestCase):
    def test_screen_corners_is_loaded_only_when_a_corner_feature_is_needed(self):
        source = (ROOT / "panelFamilies/IllogicalImpulseFamily.qml").read_text(encoding="utf-8")
        block = source.split("component: ScreenCorners {}", 1)[0].rsplit("PanelLoader {", 1)[1]

        self.assertIn("Config.options.appearance.fakeScreenRounding !== 0", block)
        self.assertIn("Config.options.sidebar.cornerOpen.enable", block)


if __name__ == "__main__":
    unittest.main()
