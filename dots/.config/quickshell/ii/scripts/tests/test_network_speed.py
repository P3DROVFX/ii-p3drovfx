from pathlib import Path
import re
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
WIDGET_DIR = REPO_ROOT / "modules/ii/bar/widgets/networkSpeed"


def widget_sources():
    return {path.name: path.read_text() for path in WIDGET_DIR.glob("*.qml")}


class WiringTests(unittest.TestCase):
    def test_widget_is_registered_with_both_styles(self):
        registry = (REPO_ROOT / "modules/common/BarComponentRegistry.qml").read_text()
        widget_registry = (REPO_ROOT / "modules/ii/bar/registry/BarWidgetRegistry.qml").read_text()
        bar_component = (REPO_ROOT / "modules/ii/bar/BarComponent.qml").read_text()
        config = (REPO_ROOT / "modules/common/Config.qml").read_text()

        self.assertIn('id: "network_speed"', registry)
        self.assertIn('styleConfigKey: "networkSpeed"', registry)
        self.assertIn('configPage: "NetworkSpeedConfig.qml"', registry)
        self.assertIn('case "network_speed":          return s.networkSpeed ?? "default";', widget_registry)
        self.assertIn('property string networkSpeed: "default"', config)
        self.assertIn("property JsonObject networkSpeed: JsonObject {", config)
        self.assertIn("NetworkSpeedWidget {", bar_component)
        self.assertIn("ExpressiveNetworkSpeed {", bar_component)
        self.assertIn('modelData.id === "network_speed" && Config.options.bar.styles.networkSpeed === "expressive"', bar_component)

    def test_settings_page_is_registered_and_reachable(self):
        settings_registry = (REPO_ROOT / "modules/common/SettingsPageRegistry.qml").read_text()
        waffle = (REPO_ROOT / "modules/settings/configs/widgets/BarWidgetsWaffleConfig.qml").read_text()
        self.assertIn('"widgets/NetworkSpeedConfig.qml"', settings_registry)
        self.assertIn('openComponentPage("network_speed")', waffle)
        self.assertTrue((REPO_ROOT / "modules/settings/configs/widgets/NetworkSpeedConfig.qml").is_file())

    def test_every_design_exists(self):
        for name in (
            "NetworkSpeedWidget.qml",
            "ExpressiveNetworkSpeed.qml",
            "NetworkSpeedCapsule.qml",
            "NetworkSpeedSplit.qml",
            "NetworkSpeedGraph.qml",
            "NetworkSpeedRows.qml",
        ):
            self.assertTrue((WIDGET_DIR / name).is_file(), name)

    def test_config_declares_every_option_the_page_edits(self):
        config = (REPO_ROOT / "modules/common/Config.qml").read_text()
        page = (REPO_ROOT / "modules/settings/configs/widgets/NetworkSpeedConfig.qml").read_text()
        block = config[config.index("property JsonObject networkSpeed: JsonObject {"):]
        block = block[: block.index("property JsonObject portWatcher")]
        for option in ("mode", "unit", "expressiveVariant", "colorMode", "showUnit", "compact", "hideWhenOffline"):
            self.assertRegex(block, rf"property \w+ {option}:")
            self.assertIn(f"networkSpeed.{option}", page)


class DesignContractTests(unittest.TestCase):
    def test_no_borders(self):
        combined = "\n".join(widget_sources().values())
        self.assertNotIn("border.width", combined)
        self.assertNotIn("border.color", combined)

    def test_no_decorative_scale_or_spin_on_hover(self):
        combined = "\n".join(widget_sources().values())
        self.assertNotIn("RotationAnimator", combined)
        for line in combined.splitlines():
            if line.strip().startswith(("scale:", "rotation:")):
                self.fail(f"decorative transform: {line.strip()}")

    def test_colours_come_from_the_shared_palette(self):
        sources = widget_sources()
        self.assertIn("BarWidgetPalette", sources["ExpressiveNetworkSpeed.qml"])
        for name in ("NetworkSpeedCapsule.qml", "NetworkSpeedSplit.qml", "NetworkSpeedGraph.qml", "NetworkSpeedRows.qml"):
            self.assertNotIn("Appearance.colors.col", sources[name].replace("Appearance.colors.colOnLayer1", ""), name)

    def test_no_palette_property_starts_with_on(self):
        for name, text in widget_sources().items():
            self.assertIsNone(re.search(r"property \w+ on[A-Z]", text), name)

    def test_expressive_slot_and_surface_share_one_driver(self):
        expressive = widget_sources()["ExpressiveNetworkSpeed.qml"]
        self.assertEqual(expressive.count("Behavior on animatedLength"), 1)
        self.assertEqual(expressive.count("Behavior on implicitWidth"), 0)
        self.assertEqual(expressive.count("Behavior on implicitHeight"), 0)

    def test_short_axis_follows_the_bar_not_an_invented_thickness(self):
        expressive = widget_sources()["ExpressiveNetworkSpeed.qml"]
        self.assertIn("Appearance.sizes.verticalBarWidth - 8", expressive)
        self.assertIn("Appearance.sizes.baseBarHeight - 8", expressive)

    def test_tooltips_work_without_an_overlay(self):
        for name, text in widget_sources().items():
            if "StyledToolTip" in text:
                self.assertIn("requireOverlay: false", text, name)

    def test_number_and_unit_stay_in_separate_labels(self):
        # StyledText picks the numbers font from a regex over the whole text.
        cell = widget_sources()["NetworkSpeedCell.qml"]
        self.assertIn("root.rate.number", cell)
        self.assertIn("id: unitText", cell)

    def test_every_design_handles_the_vertical_bar(self):
        for name in ("NetworkSpeedWidget.qml", "ExpressiveNetworkSpeed.qml", "NetworkSpeedCapsule.qml",
                     "NetworkSpeedSplit.qml", "NetworkSpeedGraph.qml", "NetworkSpeedRows.qml"):
            self.assertIn("vertical", widget_sources()[name], name)


class ServiceContractTests(unittest.TestCase):
    service = (REPO_ROOT / "services/NetworkSpeed.qml").read_text()

    def test_samples_without_spawning_a_process(self):
        self.assertIn('path: "/proc/net/dev"', self.service)
        self.assertNotIn("Process {", self.service)

    def test_widget_holds_the_sampler_by_name(self):
        readout = widget_sources()["NetworkSpeedReadout.qml"]
        self.assertIn("NetworkSpeed.setHolder(root.holderName, true)", readout)
        self.assertIn("NetworkSpeed.setHolder(root.holderName, false)", readout)
        self.assertIn("function setHolder", self.service)

    def test_wifi_dialog_api_is_kept(self):
        self.assertIn("function start()", self.service)
        self.assertIn("function stop()", self.service)
        for prop in ("downloadSpeed", "uploadSpeed", "maxSpeed"):
            self.assertIn(f"property real {prop}", self.service)


if __name__ == "__main__":
    unittest.main()
