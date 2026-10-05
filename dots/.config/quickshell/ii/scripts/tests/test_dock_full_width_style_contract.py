"""Contracts for the full width dock style.

The style is geometry, not a silhouette: the panel takes the whole main axis of
the screen, sits flush on its edge with square corners, and its content is
centred on it. `computeSizes` is the one place that decides those extents, so
these contracts pin the flags it reads, the flush branch they feed and the
centring that keeps the magnification pointer mapping honest.
"""

from pathlib import Path
import json
import unittest


ROOT = Path(__file__).resolve().parents[2]
CONFIG = (ROOT / "modules/common/Config.qml").read_text()
DOCK = (ROOT / "modules/ii/dock/Dock.qml").read_text()
DOCK_CONTENT = (ROOT / "modules/ii/dock/DockContent.qml").read_text()
DOCK_APPEARANCE_CONFIG = (ROOT / "modules/settings/configs/widgets/DockAppearanceConfig.qml").read_text()
EDIT_DOCK_PAGE = (ROOT / "modules/ii/editMode/EditDockAppearancePage.qml").read_text()

STYLE_CHAIN = 'st === "islands" || st === "dynamic_island" || st === "hug" || st === "floating" || st === "transparent" || st === "full_width" || st === "full_width_concave"'


class DockFullWidthStyleContractTests(unittest.TestCase):
    def test_config_enum_constraints_includes_full_width(self):
        self.assertIn(
            '"dock.dockStyle": ["floating", "islands", "hug", "dynamic_island", "transparent", "full_width", "full_width_concave"]',
            CONFIG,
        )

    def test_dock_content_recognises_the_style_as_attached(self):
        self.assertIn(STYLE_CHAIN, DOCK_CONTENT)
        self.assertIn('readonly property bool isFullWidth: effectiveDockStyle === "full_width" || isFullWidthConcave', DOCK_CONTENT)
        self.assertIn(
            "readonly property bool isAttachedToEdge: isDynamicIsland || isHug || isFullWidth",
            DOCK_CONTENT,
        )

    def test_dock_window_takes_the_whole_main_axis(self):
        self.assertIn("readonly property bool isFullWidth: dockContent.isFullWidth", DOCK)
        self.assertIn("const isFullWidth = opts.isFullWidth ?? false", DOCK)
        self.assertIn("const flushMainW = isFullWidth && !opts.isVertical", DOCK)
        self.assertIn("const flushMainH = isFullWidth && opts.isVertical", DOCK)
        self.assertIn("const fullDockW = Math.min(flushMainW ? maxW : baseDockW, maxW)", DOCK)
        self.assertIn("const fullDockH = Math.min(flushMainH ? maxH : baseDockH, maxH)", DOCK)
        # Nothing on the screen shortens the flush axis, and the shadow of a
        # panel locked to the edge gets the same room hug reserves for its own.
        self.assertIn("(isAttached ? 0 : gapsOut * 2) - (flushMainW ? 0 : barOffsetH)", DOCK)
        self.assertIn("const crossPad = isAttached ? ((isHug || isFullWidth) ? shadowPad : 0) : (floatingPad * 2)", DOCK)

    def test_tray_corners_are_square(self):
        """A panel flush with the screen's edge has no corner of its own."""
        self.assertIn(
            "readonly property real trayCornerRadius: (dockRoot.isDynamicIsland || dockRoot.isHug || dockRoot.isFullWidth) ? 0 : dockContent.dockCornerRadius",
            DOCK,
        )

    def test_content_is_centred_on_the_wide_tray(self):
        """The lens reads the pointer as if the base dock were centred."""
        self.assertIn(
            "contentWidth: root.isVertical ? parent.width : Math.max(unifiedRow.width, parent.width)",
            DOCK_CONTENT,
        )
        self.assertIn(
            "contentHeight: root.isVertical ? Math.max(unifiedColumn.height, parent.height) : parent.height",
            DOCK_CONTENT,
        )
        self.assertIn("anchors.horizontalCenter: root.isFullWidth ? parent.horizontalCenter : undefined", DOCK_CONTENT)
        self.assertIn("anchors.verticalCenter: root.isFullWidth ? parent.verticalCenter : undefined", DOCK_CONTENT)

    def test_settings_and_edit_mode_offer_the_style(self):
        self.assertIn(
            '{ displayName: Translation.tr("Full width"), icon: "width_full", value: "full_width" }',
            DOCK_APPEARANCE_CONFIG,
        )
        self.assertIn(STYLE_CHAIN, DOCK_APPEARANCE_CONFIG)
        self.assertIn(
            '{ "displayName": Translation.tr("Full width"), "icon": "width_full", "value": "full_width" }',
            EDIT_DOCK_PAGE,
        )
        self.assertIn(
            'stored === "islands" || stored === "dynamic_island" || stored === "hug" || stored === "floating" || stored === "transparent" || stored === "full_width" || stored === "full_width_concave"',
            EDIT_DOCK_PAGE,
        )

    def test_translations_cover_the_label(self):
        for locale, label in (("en_US", "Full width"), ("pt_BR", "Largura total")):
            strings = json.loads((ROOT / f"translations/{locale}.json").read_text())
            self.assertEqual(strings.get("Full width"), label, locale)


if __name__ == "__main__":
    unittest.main()
