from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
WIDGETS = ROOT / "modules/ii/bar/widgets"

# widget id -> (style config key, router component(s), settings page)
SCULPT = {
    "bluetooth_devices": ("bluetooth", ("SculptBluetoothDevices",), "BluetoothConfig.qml"),
    "utility_buttons": ("utilButtons", ("SculptUtilButtons",), "UtilButtonsConfig.qml"),
    "search": ("search", ("SculptSearchBarWidget",), "SearchBarWidgetConfig.qml"),
    "dashboard_panel_button": ("dashboard", ("SculptDashboardPanelButton",), "DashboardButtonConfig.qml"),
    "keyboard_layout": ("keyboard", ("SculptKeyboardLayout",), "KeyboardLayoutConfig.qml"),
    "weather": ("weather", ("SculptWeatherWidget",), "WeatherBarWidgetConfig.qml"),
    "timer": ("timer", ("SculptTimerWidget",), "IndicatorsConfig.qml"),
    "system_monitor": ("resources", ("SculptResources",), "SystemMonitorConfig.qml"),
}

DISPATCHERS = (
    WIDGETS / "bluetooth/SculptBluetoothDevices.qml",
    WIDGETS / "utilButtons/SculptUtilButtons.qml",
    WIDGETS / "search/SculptSearchBarWidget.qml",
    WIDGETS / "dashboard/SculptDashboardPanelButton.qml",
    WIDGETS / "keyboard/SculptKeyboardLayout.qml",
    WIDGETS / "weather/SculptWeatherWidget.qml",
    WIDGETS / "timer/SculptTimerWidget.qml",
    WIDGETS / "resources/SculptResources.qml",
)
FILES = tuple(sorted(WIDGETS.glob("*/Sculpt*.qml")))

# config object -> (variants, dispatcher)
VARIANTS = {
    "bluetooth": (("card", "ring", "badge"), "bluetooth/SculptBluetoothDevices.qml"),
    "utilButtons": (("toolbar", "media", "shapes"), "utilButtons/SculptUtilButtons.qml"),
    "searchWidget": (("field", "display", "split"), "search/SculptSearchBarWidget.qml"),
    "dashboardButton": (("tile", "chip", "cluster"), "dashboard/SculptDashboardPanelButton.qml"),
    "keyboardLayout": (("selector", "carousel", "dial"), "keyboard/SculptKeyboardLayout.qml"),
    "weatherWidget": (("poster", "stamp", "daylight"), "weather/SculptWeatherWidget.qml"),
    "timers": (("squeeze", "fill", "phases"), "timer/SculptTimerWidget.qml"),
    "resources": (("pressure", "bars", "trace"), "resources/SculptResources.qml"),
}


class BarSculptWidgetsContractTest(unittest.TestCase):
    def read(self, relative_path: str) -> str:
        return (ROOT / relative_path).read_text(encoding="utf-8")

    def test_every_sculpt_style_is_registered_routed_and_selectable(self):
        registry = self.read("modules/common/BarComponentRegistry.qml")
        router = self.read("modules/ii/bar/BarComponent.qml")
        for widget_id, (key, components, page) in SCULPT.items():
            entry = registry.split(f'id: "{widget_id}"', 1)[1].split('            id: "', 1)[0]
            self.assertIn('value: "sculpt"', entry, widget_id)
            for component in components:
                self.assertIn(f"{component} {{", router)
            settings = self.read(f"modules/settings/configs/widgets/{page}")
            self.assertIn('value: "sculpt"', settings, page)
            self.assertIn(f'styles.{key} === "sculpt"', settings, page)

    def test_sculpt_widgets_paint_their_own_surface(self):
        # The group chip would sit behind a surface the widget already draws.
        router = self.read("modules/ii/bar/BarComponent.qml")
        is_expressive = router.split("readonly property bool isExpressive:", 1)[1].split("readonly property bool isDefault", 1)[0]
        for key in ("bluetooth", "keyboard", "resources", "timer"):
            self.assertRegex(is_expressive, rf'styles\.{key} === "sculpt"')
        self.assertIn('Config.options.bar.styles.weather === "sculpt"', is_expressive)
        self.assertIn('["expressive", "neural", "sculpt"].includes(Config.options.bar.styles.search)', is_expressive)

    def test_no_borders_raw_colours_or_loops(self):
        for path in FILES:
            text = path.read_text(encoding="utf-8")
            self.assertNotIn("border.width", text, path.name)
            self.assertIsNone(re.search(r'color:\s*"#', text), path.name)
            self.assertNotIn("loops: Animation.Infinite", text, path.name)

    def test_colours_come_from_the_widget_palette(self):
        for path in DISPATCHERS:
            self.assertIn("BarWidgetPalette {", path.read_text(encoding="utf-8"), path.name)

    def test_every_widget_offers_three_variants(self):
        config = self.read("modules/common/Config.qml")
        for key, (variants, dispatcher) in VARIANTS.items():
            blocks = [part.split("}", 1)[0] for part in config.split(f"property JsonObject {key}: JsonObject {{")[1:]]
            self.assertTrue(any("property string sculptVariant:" in block for block in blocks), key)
            source = (WIDGETS / dispatcher).read_text(encoding="utf-8")
            self.assertIn(f"Config.options.bar.{key}.sculptVariant", source)
            for variant in variants:
                self.assertIn(f'"{variant}"', source, (dispatcher, variant))
        pages = "".join(self.read(f"modules/settings/configs/widgets/{page}") for _, _, page in SCULPT.values())
        for key, (variants, _) in VARIANTS.items():
            self.assertIn(f"Config.options.bar.{key}.sculptVariant", pages)
            for variant in variants:
                self.assertIn(f'value: "{variant}"', pages)

    def test_animated_type_axes_go_through_blend(self):
        # Every distinct axes value opens a font face: animated axes must be snapped.
        for name in ("search/SculptSearchDisplay.qml", "bluetooth/SculptBluetoothRing.qml",
                     "weather/SculptWeatherPoster.qml", "timer/SculptTimerSqueeze.qml",
                     "resources/SculptResourcesPressure.qml",
                     "keyboard/SculptKeyboardSelector.qml", "dashboard/SculptDashboardPanelButton.qml"):
            self.assertIn("Appearance.font.variableAxes.blend(", (WIDGETS / name).read_text(encoding="utf-8"), name)

    def test_utility_styles_share_one_action_list(self):
        actions = (WIDGETS / "utilButtons/UtilButtonActions.qml").read_text(encoding="utf-8")
        self.assertIn("readonly property var actions", actions)
        for name in ("SculptUtilButtons.qml", "SegmentedUtilButtons.qml"):
            self.assertIn("UtilButtonActions {", (WIDGETS / "utilButtons" / name).read_text(encoding="utf-8"))

    def test_sculpt_dashboard_lends_the_bell_to_the_icon_driver(self):
        dashboard = (WIDGETS / "dashboard/SculptDashboardPanelButton.qml").read_text(encoding="utf-8")
        self.assertIn("DashboardIconDriver {", dashboard)
        self.assertIn("notificationIcon: anchorLoader.item?.bellIcon ?? null", dashboard)
        self.assertNotIn("id: notificationRev", dashboard)
        self.assertIn("deferredContent: Component", dashboard)

    def test_strings_are_translated(self):
        for lang in ("en_US", "pt_BR"):
            data = self.read(f"translations/{lang}.json")
            for text in ("Sculpt", "Sculpt variant"):
                self.assertIn(f'"{text}":', data)


if __name__ == "__main__":
    unittest.main()


class SculptLiveValuesContractTest(unittest.TestCase):
    def test_fast_values_never_rebuild_the_readouts(self):
        # The stopwatch ticks every 10 ms and ResourceUsage samples constantly:
        # the Repeaters walk stable keys and read values through a function.
        for name, function in (("timer/SculptTimerWidget.qml", "entryFor"), ("resources/SculptResources.qml", "metricFor")):
            source = (WIDGETS / name).read_text(encoding="utf-8")
            self.assertIn("property var keys:", source)
            self.assertIn(f"property var {function}: function", source)

    def test_optional_metrics_are_only_sampled_while_shown(self):
        source = (WIDGETS / "resources/SculptResources.qml").read_text(encoding="utf-8")
        for metric in ("temperature", "disk", "swap"):
            self.assertIn(f'ResourceUsage.requestMetric("{metric}", false)', source)
