from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
WIDGET_DIR = ROOT / "modules/ii/bar/widgets/activeWindow"


class BarActiveWindowWidgetContractTest(unittest.TestCase):
    def read(self, relative_path: str) -> str:
        return (ROOT / relative_path).read_text(encoding="utf-8")

    def widget(self, name: str) -> str:
        return (WIDGET_DIR / name).read_text(encoding="utf-8")

    def test_config_defines_animate_transition_options(self):
        config = self.read("modules/common/Config.qml")
        self.assertIn("property JsonObject activeWindow:", config)
        active_window_block = config.split("property JsonObject activeWindow:", 1)[1].split("}", 1)[0]
        self.assertIn("property bool animateTransition: true", active_window_block)

    def test_active_window_implements_slide_and_fade_transition(self):
        content = self.widget("ActiveWindow.qml")
        self.assertIn("travelDistance: 24", content)
        self.assertIn("animDuration", content)
        self.assertIn("transitionAnim", content)
        self.assertIn("ParallelAnimation", content)
        self.assertIn("incomingWrapper", content)
        self.assertIn("outgoingWrapper", content)
        self.assertIn("Easing.OutQuad", content)
        self.assertIn("activeWsId", content)
        self.assertIn("currentDisplayedWsId", content)
        self.assertIn("slideSign", content)
        self.assertIn("targetWsId > root.currentDisplayedWsId", content)

        # Opacity fade
        self.assertIn('property: "opacity"', content)

        # Dynamic workspace slide: horizontal (X) and vertical (Y)
        self.assertIn("to: root.vertical ? 0 : (root.slideSign * root.travelDistance)", content)
        self.assertIn("to: root.vertical ? (root.slideSign * root.travelDistance) : 0", content)
        self.assertIn("from: root.vertical ? 0 : (-root.slideSign * root.travelDistance)", content)
        self.assertIn("from: root.vertical ? (-root.slideSign * root.travelDistance) : 0", content)

    def test_expressive_active_window_implements_slide_and_fade_transition(self):
        content = self.widget("ExpressiveActiveWindow.qml")
        self.assertIn("travelDistance: 24", content)
        self.assertIn("animDuration", content)
        self.assertIn("transitionAnim", content)
        self.assertIn("ParallelAnimation", content)
        self.assertIn("incomingWrapper", content)
        self.assertIn("outgoingWrapper", content)
        self.assertIn("Easing.OutQuad", content)
        self.assertIn("activeWsId", content)
        self.assertIn("currentDisplayedWsId", content)
        self.assertIn("slideSign", content)
        self.assertIn("targetWsId > root.currentDisplayedWsId", content)

        # Opacity fade
        self.assertIn('property: "opacity"', content)

        # Dynamic workspace slide: horizontal (X) and vertical (Y)
        self.assertIn("to: root.vertical ? 0 : (root.slideSign * root.travelDistance)", content)
        self.assertIn("to: root.vertical ? (root.slideSign * root.travelDistance) : 0", content)
        self.assertIn("from: root.vertical ? 0 : (-root.slideSign * root.travelDistance)", content)
        self.assertIn("from: root.vertical ? (-root.slideSign * root.travelDistance) : 0", content)

    def test_settings_page_exposes_animation_toggles(self):
        page = self.read("modules/settings/configs/widgets/ActiveWindowConfig.qml")
        self.assertIn("Config.options.bar.activeWindow.animateTransition", page)
        self.assertIn('text: Translation.tr("Animate title change")', page)


if __name__ == "__main__":
    unittest.main()

