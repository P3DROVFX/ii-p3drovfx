import unittest
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent.parent
CATALOG_PATH = ROOT / "modules/common/quickToggles/androidStyle/QuickToggleCatalog.js"
RESIZE_PATH = ROOT / "modules/common/quickToggles/androidStyle/QuickToggleResize.js"
CHOOSER_PATH = ROOT / "modules/common/quickToggles/androidStyle/AndroidToggleDelegateChooser.qml"
ICON_TOGGLE_PATH = ROOT / "modules/common/quickToggles/androidStyle/weather/AndroidWeatherIconShapeToggle.qml"
CARD_TOGGLE_PATH = ROOT / "modules/common/quickToggles/androidStyle/weather/AndroidWeatherCardToggle.qml"


class WeatherQuickToggleContractTest(unittest.TestCase):
    def test_catalog_freeform_weather_widgets(self):
        catalog_text = CATALOG_PATH.read_text(encoding="utf-8")
        self.assertIn("weatherIconShape: {", catalog_text)
        self.assertIn("weatherCard: {", catalog_text)

        icon_def = catalog_text.split("weatherIconShape: {")[1].split("}")[0]
        self.assertNotIn("allowedSizes", icon_def)

        card_def = catalog_text.split("weatherCard: {")[1].split("}")[0]
        self.assertNotIn("allowedSizes", card_def)

    def test_freeform_sizing_in_catalog(self):
        node_script = f"""
        const fs = require('fs');
        let catalogCode = fs.readFileSync('{CATALOG_PATH}', 'utf8');
        catalogCode = catalogCode.replace('.pragma library', '');
        catalogCode = catalogCode.replace(/var TOGGLE_TYPES =/, 'var TOGGLE_TYPES = global.TOGGLE_TYPES =');
        eval(catalogCode);
        let resizeCode = fs.readFileSync('{RESIZE_PATH}', 'utf8');
        resizeCode = resizeCode.replace('.pragma library', '');
        resizeCode = resizeCode.replace('.import "QuickToggleCatalog.js" as Catalog', 'var Catalog = {{ kind, isSizeAllowed, normalizeSize }};');
        eval(resizeCode);

        const types = ['weatherIconShape', 'weatherCard'];
        const testSizes = [[1, 1], [2, 1], [3, 1], [4, 1], [1, 2], [2, 2], [3, 2], [4, 2], [1, 3], [2, 3], [1, 4], [2, 4], [4, 4]];
        for (const t of types) {{
            for (const [w, h] of testSizes) {{
                const norm = normalizeSize(t, w, h, 6);
                if (norm[0] !== w || norm[1] !== h) {{
                    console.error('Mismatch for ' + t + ' [' + w + ', ' + h + ']: got [' + norm + ']');
                    process.exit(1);
                }}
                if (!isSizeAllowed(t, w, h, 6)) {{
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

    def test_chooser_contains_weather_delegates(self):
        chooser_text = CHOOSER_PATH.read_text(encoding="utf-8")
        self.assertIn('roleValue: "weatherIconShape"', chooser_text)
        self.assertIn("AndroidWeatherIconShapeToggle {", chooser_text)
        self.assertIn('roleValue: "weatherCard"', chooser_text)
        self.assertIn("AndroidWeatherCardToggle {", chooser_text)

    def test_weather_icon_toggle_adaptive_stages(self):
        icon_text = ICON_TOGGLE_PATH.read_text(encoding="utf-8")
        self.assertIn("isHorizontal", icon_text)
        self.assertIn("isVertical", icon_text)
        self.assertIn("isSquare", icon_text)
        self.assertIn("MaterialShape", icon_text)
        self.assertIn("WeatherIcons.getWeatherIcon", icon_text)

    def test_weather_card_toggle_adaptive_stages(self):
        card_text = CARD_TOGGLE_PATH.read_text(encoding="utf-8")
        self.assertIn("isNarrow", card_text)
        self.assertIn("isShort", card_text)
        self.assertIn("dayRows", card_text)
        self.assertIn("Repeater", card_text)
        self.assertIn("WeatherIcons.getWeatherIcon", card_text)


if __name__ == "__main__":
    unittest.main()
