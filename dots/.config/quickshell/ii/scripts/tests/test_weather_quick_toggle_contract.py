import unittest
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent.parent
CATALOG_PATH = ROOT / "modules/common/quickToggles/androidStyle/QuickToggleCatalog.js"
RESIZE_PATH = ROOT / "modules/common/quickToggles/androidStyle/QuickToggleResize.js"
CHOOSER_PATH = ROOT / "modules/common/quickToggles/androidStyle/AndroidToggleDelegateChooser.qml"
TRAY_PREVIEW_PATH = ROOT / "modules/common/quickToggles/androidStyle/QuickToggleTrayPreview.qml"

ICON_TOGGLE_PATH = ROOT / "modules/common/quickToggles/androidStyle/weather/AndroidWeatherIconShapeToggle.qml"
CARD_TOGGLE_PATH = ROOT / "modules/common/quickToggles/androidStyle/weather/AndroidWeatherCardToggle.qml"
WIDGET_TOGGLE_PATH = ROOT / "modules/common/quickToggles/androidStyle/weather/AndroidWeatherWidgetToggle.qml"
CIRCLE_TOGGLE_PATH = ROOT / "modules/common/quickToggles/androidStyle/weather/AndroidWeatherCircleToggle.qml"
TYPOGRAPHY_TOGGLE_PATH = ROOT / "modules/common/quickToggles/androidStyle/weather/AndroidWeatherTypographyToggle.qml"
FORECAST_TOGGLE_PATH = ROOT / "modules/common/quickToggles/androidStyle/weather/AndroidWeatherForecastToggle.qml"


class WeatherQuickToggleContractTest(unittest.TestCase):
    def test_catalog_all_weather_variants(self):
        catalog_text = CATALOG_PATH.read_text(encoding="utf-8")
        variants = ["weatherIconShape", "weatherCard", "weatherWidget", "weatherCircle", "weatherTypography", "weatherForecast"]
        for v in variants:
            self.assertIn(f"{v}: {{", catalog_text, f"{v} missing in catalog")
            self.assertIn('variantGroup: "weather"', catalog_text)

            v_def = catalog_text.split(f"{v}: {{")[1].split("}")[0]
            self.assertNotIn("allowedSizes", v_def, f"{v} should be freeform")

    def test_freeform_sizing_for_all_weather_variants_in_catalog(self):
        node_script = f"""
        const fs = require('fs');
        const vm = require('vm');
        const ctx = {{ global: {{}}, console, process }};
        ctx.global = ctx;
        vm.createContext(ctx);

        let catalogCode = fs.readFileSync('{CATALOG_PATH}', 'utf8');
        catalogCode = catalogCode.replace('.pragma library', '');
        vm.runInContext(catalogCode, ctx);

        let resizeCode = fs.readFileSync('{RESIZE_PATH}', 'utf8');
        resizeCode = resizeCode.replace('.pragma library', '');
        resizeCode = resizeCode.replace('.import "QuickToggleCatalog.js" as Catalog', 'var Catalog = {{ kind, isSizeAllowed, normalizeSize }};');
        vm.runInContext(resizeCode, ctx);

        const allTypes = ['weatherIconShape', 'weatherCard', 'weatherWidget', 'weatherCircle', 'weatherTypography', 'weatherForecast'];
        const testSizes = [[1, 1], [2, 1], [3, 1], [4, 1], [1, 2], [2, 2], [3, 2], [4, 2], [1, 3], [2, 3], [1, 4], [2, 4], [4, 4]];
        for (const t of allTypes) {{
            for (const [w, h] of testSizes) {{
                const norm = ctx.normalizeSize(t, w, h, 6);
                if (norm[0] !== w || norm[1] !== h) {{
                    console.error('Mismatch for ' + t + ' [' + w + ', ' + h + ']: got [' + norm + ']');
                    process.exit(1);
                }}
                if (!ctx.isSizeAllowed(t, w, h, 6)) {{
                    console.error('Not allowed for ' + t + ' [' + w + ', ' + h + ']');
                    process.exit(2);
                }}
            }}
        }}

        console.log('OK');
        """
        res = subprocess.run(["node", "-e", node_script], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"Node script error: {res.stderr}")
        self.assertIn("OK", res.stdout)

    def test_chooser_contains_all_weather_delegates(self):
        chooser_text = CHOOSER_PATH.read_text(encoding="utf-8")
        expected = [
            ("weatherIconShape", "AndroidWeatherIconShapeToggle"),
            ("weatherCard", "AndroidWeatherCardToggle"),
            ("weatherWidget", "AndroidWeatherWidgetToggle"),
            ("weatherCircle", "AndroidWeatherCircleToggle"),
            ("weatherTypography", "AndroidWeatherTypographyToggle"),
            ("weatherForecast", "AndroidWeatherForecastToggle"),
        ]
        for role, component in expected:
            self.assertIn(f'roleValue: "{role}"', chooser_text)
            self.assertIn(f"{component} {{", chooser_text)

    def test_tray_preview_metadata_contains_all_weather_variants(self):
        tray_text = TRAY_PREVIEW_PATH.read_text(encoding="utf-8")
        variants = ["weatherIconShape", "weatherCard", "weatherWidget", "weatherCircle", "weatherTypography", "weatherForecast"]
        for v in variants:
            self.assertIn(f"{v}: {{", tray_text)

    def test_weather_components_exist_and_conform(self):
        self.assertTrue(ICON_TOGGLE_PATH.exists())
        self.assertTrue(CARD_TOGGLE_PATH.exists())
        self.assertTrue(WIDGET_TOGGLE_PATH.exists())
        self.assertTrue(CIRCLE_TOGGLE_PATH.exists())
        self.assertTrue(TYPOGRAPHY_TOGGLE_PATH.exists())
        self.assertTrue(FORECAST_TOGGLE_PATH.exists())

        # Widget Toggle
        w_text = WIDGET_TOGGLE_PATH.read_text(encoding="utf-8")
        self.assertIn("MaterialShape", w_text)
        self.assertIn("WeatherIcons.getWeatherIcon", w_text)

        # Circle Toggle
        c_text = CIRCLE_TOGGLE_PATH.read_text(encoding="utf-8")
        self.assertIn("Cookie12Sided", c_text)
        self.assertIn("outerCircle", c_text)

        # Typography Toggle
        t_text = TYPOGRAPHY_TOGGLE_PATH.read_text(encoding="utf-8")
        self.assertIn("now", t_text)
        self.assertIn("cityName", t_text)

        # Forecast Toggle
        f_text = FORECAST_TOGGLE_PATH.read_text(encoding="utf-8")
        self.assertIn("isVertical", f_text)
        self.assertIn("leftHeroCard", f_text)
        self.assertIn("dayPill", f_text)


if __name__ == "__main__":
    unittest.main()
