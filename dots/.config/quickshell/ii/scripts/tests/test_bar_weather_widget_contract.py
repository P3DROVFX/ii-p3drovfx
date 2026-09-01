from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
WEATHER_DIR = ROOT / "modules/ii/bar/widgets/weather"


class BarWeatherWidgetContractTest(unittest.TestCase):
    def read(self, relative_path: str) -> str:
        return (ROOT / relative_path).read_text(encoding="utf-8")

    def test_registry_exposes_both_new_weather_families(self):
        registry = self.read("modules/common/BarComponentRegistry.qml")
        weather_entry = registry.split('id: "weather"', 1)[1].split('id: "utility_buttons"', 1)[0]

        for style in ("default", "expressive", "horizon", "tessera"):
            self.assertIn(f'value: "{style}"', weather_entry)
        self.assertIn('configPage: "WeatherBarWidgetConfig.qml"', weather_entry)

    def test_weather_variants_are_persisted_with_explicit_strings(self):
        config = self.read("modules/common/Config.qml")
        self.assertIn("property JsonObject weatherWidget: JsonObject", config)
        self.assertIn('property string horizonVariant: "balanced"', config)
        self.assertIn('property string tesseraVariant: "paired"', config)
        self.assertIn('property string colorMode: "tonal"', config)

    def test_router_loads_new_components_as_paddingless_surfaces(self):
        router = self.read("modules/ii/bar/BarComponent.qml")
        self.assertIn('style === "horizon"', router)
        self.assertIn('style === "tessera"', router)
        self.assertIn("HorizonWeatherWidget", router)
        self.assertIn("TesseraWeatherWidget", router)
        self.assertIn('Config.options.bar.styles.weather === "horizon"', router)
        self.assertIn('Config.options.bar.styles.weather === "tessera"', router)

    def test_settings_page_exposes_three_variants_per_family(self):
        page = self.read("modules/settings/configs/widgets/WeatherBarWidgetConfig.qml")
        for value in ("balanced", "inverted", "minimal"):
            self.assertIn(f'value: "{value}"', page)
        for value in ("paired", "contrast", "bare"):
            self.assertIn(f'value: "{value}"', page)
        for value in ("tonal", "vibrant", "neutral"):
            self.assertIn(f'value: "{value}"', page)
        self.assertIn('pageId: "weather"', page)

    def test_new_designs_avoid_repeated_visual_devices(self):
        bodies = "\n".join(
            (WEATHER_DIR / filename).read_text(encoding="utf-8")
            for filename in ("HorizonWeatherWidget.qml", "TesseraWeatherWidget.qml")
        )
        for forbidden in (
            "CircularProgress",
            "StyledCircularProgress",
            "border.width",
            "border.color",
            "loops: Animation.Infinite",
            "scale:",
        ):
            self.assertNotIn(forbidden, bodies)
        self.assertIn("Appearance.sizes.baseBarHeight - 8", bodies)
        self.assertIn("Appearance.sizes.verticalBarWidth - 8", bodies)

    def test_new_designs_only_render_icon_and_temperature(self):
        bodies = "\n".join(
            (WEATHER_DIR / filename).read_text(encoding="utf-8")
            for filename in ("HorizonWeatherWidget.qml", "TesseraWeatherWidget.qml")
        )
        self.assertIn("WeatherIcons.getWeatherIcon", bodies)
        self.assertIn("Weather.data?.temp", bodies)
        for extra_reading in (
            "Weather.forecastData",
            "Weather.data?.humidity",
            "Weather.data?.wind",
            "Weather.data?.windDir",
            "Weather.data?.sunrise",
            "Weather.data?.sunset",
            "Weather.data?.wDesc",
        ):
            self.assertNotIn(extra_reading, bodies)

    def test_horizon_is_a_bare_rail_not_an_expressive_pill(self):
        horizon = (WEATHER_DIR / "HorizonWeatherWidget.qml").read_text(encoding="utf-8")
        self.assertNotIn("RippleButton", horizon)
        self.assertIn("id: horizonRail", horizon)
        self.assertIn("palette.bare", horizon)
        self.assertIn("palette.bareAccent", horizon)

    def test_vertical_temperature_rotates_inward_and_owns_long_axis(self):
        for filename in ("HorizonWeatherWidget.qml", "TesseraWeatherWidget.qml"):
            body = (WEATHER_DIR / filename).read_text(encoding="utf-8")
            self.assertIn("readonly property int contentRotation", body)
            self.assertIn("rotation: root.contentRotation", body)

        tessera = (WEATHER_DIR / "TesseraWeatherWidget.qml").read_text(encoding="utf-8")
        self.assertIn("temperatureText.implicitWidth +", tessera)

    def test_tessera_temperature_uses_container_pair_and_vertical_pill_ratio(self):
        tessera = (WEATHER_DIR / "TesseraWeatherWidget.qml").read_text(encoding="utf-8")
        temperature_block = tessera.split("id: temperatureTile", 1)[1]

        self.assertIn("root.thickness * 0.72", temperature_block)
        self.assertIn("Appearance.sizes.elevationMargin * 1.6", temperature_block)
        self.assertIn("radius: Appearance.rounding.full", temperature_block)
        self.assertIn("color: palette.container", temperature_block)
        self.assertIn("ColorUtils.categoryOnColor(palette.container)", temperature_block)
        self.assertNotIn("palette.onContainer", temperature_block)
        self.assertNotIn("palette.onAccent", temperature_block)

    def test_new_designs_keep_weather_interactions(self):
        for filename in ("HorizonWeatherWidget.qml", "TesseraWeatherWidget.qml"):
            body = (WEATHER_DIR / filename).read_text(encoding="utf-8")
            self.assertIn("Weather.refreshManually()", body)
            self.assertIn("WeatherPopup", body)
            self.assertIn("hoverTarget:", body)


if __name__ == "__main__":
    unittest.main()
