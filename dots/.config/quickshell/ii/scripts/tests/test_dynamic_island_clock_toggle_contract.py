import unittest
from pathlib import Path
import json
import subprocess

ROOT = Path(__file__).resolve().parent.parent.parent
CATALOG_PATH = ROOT / "modules/common/quickToggles/androidStyle/QuickToggleCatalog.js"
RESIZE_PATH = ROOT / "modules/common/quickToggles/androidStyle/QuickToggleResize.js"
CHOOSER_PATH = ROOT / "modules/common/quickToggles/androidStyle/AndroidToggleDelegateChooser.qml"
CLOCK_TOGGLE_PATH = ROOT / "modules/common/quickToggles/androidStyle/AndroidClockToggle.qml"


class DynamicIslandClockToggleContractTest(unittest.TestCase):
    def test_catalog_freeform_clock_widget_registered(self):
        catalog_text = CATALOG_PATH.read_text(encoding="utf-8")
        self.assertIn("clockWidget: {", catalog_text)
        self.assertIn('kind: "widget"', catalog_text)
        self.assertIn("defaultSize: [2, 1]", catalog_text)
        # Verify freeform: no restrictive allowedSizes array on clockWidget
        clock_def = catalog_text.split("clockWidget: {")[1].split("}")[0]
        self.assertNotIn("allowedSizes", clock_def)

    def test_catalog_allows_arbitrary_sizes_min_1x1(self):
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

        const testSizes = [[1, 1], [2, 1], [3, 1], [4, 1], [2, 2], [3, 2], [4, 2], [1, 2], [2, 4], [3, 6]];
        for (const [w, h] of testSizes) {{
            const norm = normalizeSize('clockWidget', w, h, 6);
            if (norm[0] !== w || norm[1] !== h) {{
                console.error(`Mismatch for [${{w}}, ${{h}}]: got [${{norm}}]`);
                process.exit(1);
            }}
            if (!isSizeAllowed('clockWidget', w, h, 6)) {{
                console.error(`Not allowed for [${{w}}, ${{h}}]`);
                process.exit(2);
            }}
        }}

        // Verify minimum constraint: 0x0 or 0x1 must normalize to at least 1x1
        const minNorm = normalizeSize('clockWidget', 0, 0, 6);
        if (minNorm[0] < 1 || minNorm[1] < 1) {{
            console.error(`Min size violated: got [${{minNorm}}]`);
            process.exit(3);
        }}
        console.log('OK');
        """
        res = subprocess.run(["node", "-e", node_script], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"Node script error: {res.stderr}")
        self.assertIn("OK", res.stdout)

    def test_chooser_contains_clock_widget_delegate(self):
        chooser_text = CHOOSER_PATH.read_text(encoding="utf-8")
        self.assertIn('roleValue: "clockWidget"', chooser_text)
        self.assertIn("AndroidClockToggle {", chooser_text)

    def test_clock_toggle_responsive_geometry_and_stencil_contracts(self):
        qml_text = CLOCK_TOGGLE_PATH.read_text(encoding="utf-8")

        # Orientation detection
        self.assertIn("readonly property bool isHorizontal: visualButton.width > visualButton.height", qml_text)

        # Horizontal mode: text adapts to vertical space, centered with side margins
        self.assertIn("id: horiStage", qml_text)
        self.assertIn("anchors.centerIn: parent", qml_text)
        self.assertIn("height: Math.min(maxAvailableH, maxAvailableW / designRatio)", qml_text)
        self.assertIn("width: height * designRatio", qml_text)
        self.assertIn("glyphSize: height * 0.84", qml_text)
        self.assertIn("horizontalPadding: Math.max(18", qml_text)

        # Vertical mode: text adapts to horizontal space, centered with top/bottom margins
        self.assertIn("id: flexStage", qml_text)
        self.assertIn("width: Math.min(maxAvailableW, maxAvailableH * designRatio)", qml_text)
        self.assertIn("height: width / designRatio", qml_text)
        self.assertIn("base: width / 0.96", qml_text)
        self.assertIn("glyphPixelSize: base * 0.66", qml_text)

        # Stencil mask contracts
        self.assertIn("OpacityMask {", qml_text)
        self.assertIn('family: "Google Sans Flex"', qml_text)


if __name__ == "__main__":
    unittest.main()
