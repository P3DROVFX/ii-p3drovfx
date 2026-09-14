"""Contracts for the transparent dock style."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
CONFIG = (ROOT / "modules/common/Config.qml").read_text()
DOCK = (ROOT / "modules/ii/dock/Dock.qml").read_text()
DOCK_CONTENT = (ROOT / "modules/ii/dock/DockContent.qml").read_text()
DOCK_APPEARANCE_CONFIG = (ROOT / "modules/settings/configs/widgets/DockAppearanceConfig.qml").read_text()
EDIT_DOCK_PAGE = (ROOT / "modules/ii/editMode/EditDockAppearancePage.qml").read_text()


class DockTransparentStyleContractTests(unittest.TestCase):
    def test_config_enum_constraints_includes_transparent_dock_style(self):
        """dock.dockStyle must include transparent in enumConstraints."""
        self.assertIn(
            '"dock.dockStyle": ["floating", "islands", "hug", "dynamic_island", "transparent"]',
            CONFIG,
        )

    def test_dock_content_supports_transparent_style(self):
        """DockContent must recognize 'transparent' and expose isTransparent."""
        self.assertIn(
            'st === "islands" || st === "dynamic_island" || st === "hug" || st === "floating" || st === "transparent"',
            DOCK_CONTENT,
        )
        self.assertIn(
            'readonly property bool isTransparent: effectiveDockStyle === "transparent"',
            DOCK_CONTENT,
        )

    def test_dock_window_applies_transparent_surface(self):
        """Dock.qml must expose isTransparent and hide background/shadow when transparent."""
        self.assertIn(
            "readonly property bool isTransparent: dockContent.isTransparent",
            DOCK,
        )
        self.assertIn(
            'color: (dockRoot.isDynamicIsland || dockRoot.isTransparent) ? "transparent" : Appearance.colors.colLayer0',
            DOCK,
        )
        self.assertIn(
            "opacity: (dockContent.islandsStyle || dockRoot.isTransparent) ? 0.0 : 1.0",
            DOCK,
        )
        self.assertIn(
            "!dockRoot.isTransparent",
            DOCK,
        )

    def test_settings_appearance_includes_transparent_option(self):
        """DockAppearanceConfig must expose Transparent option with opacity icon."""
        self.assertIn(
            '{ displayName: Translation.tr("Transparent"), icon: "opacity", value: "transparent" }',
            DOCK_APPEARANCE_CONFIG,
        )
        self.assertIn(
            'st === "islands" || st === "dynamic_island" || st === "hug" || st === "floating" || st === "transparent"',
            DOCK_APPEARANCE_CONFIG,
        )

    def test_edit_mode_includes_transparent_option(self):
        """EditDockAppearancePage must expose Transparent chip with opacity icon."""
        self.assertIn(
            '{ "displayName": Translation.tr("Transparent"), "icon": "opacity", "value": "transparent" }',
            EDIT_DOCK_PAGE,
        )
        self.assertIn(
            'stored === "islands" || stored === "dynamic_island" || stored === "hug" || stored === "floating" || stored === "transparent"',
            EDIT_DOCK_PAGE,
        )


if __name__ == "__main__":
    unittest.main()
