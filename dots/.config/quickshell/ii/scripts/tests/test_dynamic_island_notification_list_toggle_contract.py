import unittest
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent.parent
CATALOG_PATH = ROOT / "modules/common/quickToggles/androidStyle/QuickToggleCatalog.js"
RESIZE_PATH = ROOT / "modules/common/quickToggles/androidStyle/QuickToggleResize.js"
CHOOSER_PATH = ROOT / "modules/common/quickToggles/androidStyle/AndroidToggleDelegateChooser.qml"
NOTIFICATION_TOGGLE_PATH = ROOT / "modules/common/quickToggles/androidStyle/AndroidNotificationListToggle.qml"


class DynamicIslandNotificationListToggleContractTest(unittest.TestCase):
    def test_catalog_notification_list_widget_registered(self):
        catalog_text = CATALOG_PATH.read_text(encoding="utf-8")
        self.assertIn("notificationListWidget: {", catalog_text)
        self.assertIn('kind: "widget"', catalog_text)
        self.assertIn("defaultSize: [4, 4]", catalog_text)
        self.assertIn("minWidth: 4", catalog_text)
        self.assertIn('families: ["island"]', catalog_text)

    def test_catalog_family_exclusivity(self):
        node_script = f"""
        const fs = require('fs');
        let catalogCode = fs.readFileSync('{CATALOG_PATH}', 'utf8');
        catalogCode = catalogCode.replace('.pragma library', '');
        catalogCode = catalogCode.replace(/var TOGGLE_TYPES =/, 'var TOGGLE_TYPES = global.TOGGLE_TYPES =');
        eval(catalogCode);

        if (!availableForFamily('notificationListWidget', 'island')) {{
            console.error('Expected notificationListWidget to be available for island');
            process.exit(1);
        }}
        if (availableForFamily('notificationListWidget', 'ii')) {{
            console.error('Expected notificationListWidget to NOT be available for ii sidebar');
            process.exit(2);
        }}
        if (availableForFamily('notificationListWidget', 'tablet')) {{
            console.error('Expected notificationListWidget to NOT be available for tablet');
            process.exit(3);
        }}
        console.log('OK');
        """
        res = subprocess.run(["node", "-e", node_script], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"Node script error: {res.stderr}")
        self.assertIn("OK", res.stdout)

    def test_catalog_canonical_aliases(self):
        node_script = f"""
        const fs = require('fs');
        let catalogCode = fs.readFileSync('{CATALOG_PATH}', 'utf8');
        catalogCode = catalogCode.replace('.pragma library', '');
        catalogCode = catalogCode.replace(/var TOGGLE_TYPES =/, 'var TOGGLE_TYPES = global.TOGGLE_TYPES =');
        eval(catalogCode);

        const aliases = ['notificationListWidget', 'notificationWidget', 'notificationsWidget', 'notificationList', 'notificationsList'];
        for (const alias of aliases) {{
            if (canonicalType(alias) !== 'notificationListWidget') {{
                console.error(`Alias mismatch for ${{alias}}: got ${{canonicalType(alias)}}`);
                process.exit(1);
            }}
        }}
        console.log('OK');
        """
        res = subprocess.run(["node", "-e", node_script], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"Node script error: {res.stderr}")
        self.assertIn("OK", res.stdout)

    def test_catalog_allows_4xY_and_enforces_min_4_columns(self):
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

        // Allowed 4xY, 5xY, 6xY in a 6-column grid
        const validSizes = [
            [4, 1], [4, 2], [4, 3], [4, 4], [4, 5], [4, 6], [4, 7], [4, 8],
            [5, 1], [5, 2], [5, 4], [6, 1], [6, 4], [6, 6]
        ];
        for (const [w, h] of validSizes) {{
            const norm = normalizeSize('notificationListWidget', w, h, 6);
            if (norm[0] !== w || norm[1] !== h) {{
                console.error(`Mismatch for [${{w}}, ${{h}}]: got [${{norm}}]`);
                process.exit(1);
            }}
            if (!isSizeAllowed('notificationListWidget', w, h, 6)) {{
                console.error(`Valid size not allowed for [${{w}}, ${{h}}]`);
                process.exit(2);
            }}
        }}

        // Disallowed sizes < 4 columns in 6-column grid
        const invalidWidths = [[1, 1], [2, 2], [3, 3], [2, 4], [1, 8]];
        for (const [w, h] of invalidWidths) {{
            if (isSizeAllowed('notificationListWidget', w, h, 6)) {{
                console.error(`Width < 4 should NOT be allowed: [${{w}}, ${{h}}]`);
                process.exit(3);
            }}
            const norm = normalizeSize('notificationListWidget', w, h, 6);
            if (norm[0] < 4) {{
                console.error(`Normalization should clamp width to at least 4: got [${{norm}}]`);
                process.exit(4);
            }}
        }}

        // Verify Resize bounds correctly starts at minW = 4
        const limits = bounds('notificationListWidget', 6);
        if (limits.minW !== 4 || limits.maxW !== 6 || limits.minH !== 1 || limits.maxH !== 8) {{
            console.error(`Resize bounds mismatch: got ${{JSON.stringify(limits)}}`);
            process.exit(5);
        }}

        console.log('OK');
        """
        res = subprocess.run(["node", "-e", node_script], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"Node script error: {res.stderr}")
        self.assertIn("OK", res.stdout)

    def test_chooser_contains_notification_list_delegates(self):
        chooser_text = CHOOSER_PATH.read_text(encoding="utf-8")
        self.assertIn('roleValue: "notificationListWidget"', chooser_text)
        self.assertIn('roleValue: "notificationWidget"', chooser_text)
        self.assertIn('roleValue: "notificationsWidget"', chooser_text)
        self.assertIn('roleValue: "notificationList"', chooser_text)
        self.assertIn('roleValue: "notificationsList"', chooser_text)
        self.assertIn("AndroidNotificationListToggle {", chooser_text)

    def test_notification_toggle_qml_structure(self):
        qml_text = NOTIFICATION_TOGGLE_PATH.read_text(encoding="utf-8")
        self.assertIn("import qs.modules.common.notifications", qml_text)
        self.assertIn("NotificationList {", qml_text)
        self.assertIn("EditableQuickToggleItem {", qml_text)
        self.assertIn("id: visualButton", qml_text)
        self.assertIn('type ?? "notificationListWidget"', qml_text)
        self.assertIn("readonly property int effectiveSizeW: root.catalogSize[0]", qml_text)
        self.assertIn("readonly property int effectiveSizeH: root.catalogSize[1]", qml_text)


if __name__ == "__main__":
    unittest.main()
