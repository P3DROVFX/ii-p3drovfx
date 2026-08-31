"""Contracts for the background widgets overview zoom and transform synchronization.

Ensures that BackgroundWidgetsWindow and BackgroundRoot consume the unified
OverviewBackgroundController for all presets (including Gnome-like zoom out and
Material Shape masking), preventing fork/legacy controllers from causing inverse
zoom (scale-up) or misaligned masks/origins during overview animations.
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
BG_WIDGETS_WINDOW = (ROOT / "modules/ii/background/BackgroundWidgetsWindow.qml").read_text()
BG_ROOT = (ROOT / "modules/ii/background/BackgroundRoot.qml").read_text()
WALLPAPER_IMAGE = (ROOT / "modules/ii/background/wallpaper/WallpaperImage.qml").read_text()
OVERVIEW_BG_CONTROLLER = (ROOT / "modules/ii/background/overview/OverviewBackgroundController.qml").read_text()
OVERVIEW_ZOOM_CONTROLLER = (ROOT / "modules/ii/background/overview/OverviewZoomController.qml").read_text()
OVERVIEW_WINDOW_TRANSITION = (ROOT / "modules/ii/overview/OverviewWindowTransition.qml").read_text()


class OverviewBackgroundWidgetsZoomContractTests(unittest.TestCase):
    def test_background_widgets_window_uses_unified_overview_controller(self):
        """BackgroundWidgetsWindow must not use a bifurcated OverviewZoomController for Gnome."""
        self.assertNotIn("OverviewZoomController", BG_WIDGETS_WINDOW)
        self.assertNotIn("gnomeOverviewController", BG_WIDGETS_WINDOW)

        # Scale transform must directly read overviewController
        self.assertIn("origin.x: bgWidgetsWindow.overviewController ? bgWidgetsWindow.overviewController.scaleOriginX : bgWidgetsWindow.width / 2", BG_WIDGETS_WINDOW)
        self.assertIn("origin.y: bgWidgetsWindow.overviewController ? bgWidgetsWindow.overviewController.scaleOriginY : bgWidgetsWindow.height / 2", BG_WIDGETS_WINDOW)
        self.assertIn("xScale: bgWidgetsWindow.overviewController && bgWidgetsWindow.overviewController.followWidgetsScale ? bgWidgetsWindow.overviewController.scale : 1.0", BG_WIDGETS_WINDOW)
        self.assertIn("yScale: bgWidgetsWindow.overviewController && bgWidgetsWindow.overviewController.followWidgetsScale ? bgWidgetsWindow.overviewController.scale : 1.0", BG_WIDGETS_WINDOW)

    def test_background_widgets_window_supports_directional_translation(self):
        """Directional overview preset translates widgets with the wallpaper."""
        self.assertIn("x: bgWidgetsWindow.overviewController && bgWidgetsWindow.overviewController.followWidgetsTranslation ? bgWidgetsWindow.overviewController.translateX : 0", BG_WIDGETS_WINDOW)
        self.assertIn("y: bgWidgetsWindow.overviewController && bgWidgetsWindow.overviewController.followWidgetsTranslation ? bgWidgetsWindow.overviewController.translateY : 0", BG_WIDGETS_WINDOW)

    def test_background_widgets_window_applies_material_shape_mask(self):
        """Material Shape overview preset masks widgets to match the central shape cut."""
        self.assertIn("import QtQuick.Effects", BG_WIDGETS_WINDOW)
        self.assertIn("readonly property bool isMaterialShapeOverview: overviewController && overviewController.isMaterialShape && overviewAnimationVisible", BG_WIDGETS_WINDOW)
        self.assertIn("id: materialShapeMaskContainer", BG_WIDGETS_WINDOW)
        self.assertIn("id: materialShapeMaskSource", BG_WIDGETS_WINDOW)
        self.assertIn("layer.enabled: bgWidgetsWindow.isMaterialShapeOverview", BG_WIDGETS_WINDOW)
        self.assertIn("maskSource: materialShapeMaskSource", BG_WIDGETS_WINDOW)

    def test_background_root_unifies_transform_clock_to_overview_controller(self):
        """BackgroundRoot must not instantiate duplicate OverviewZoomController."""
        self.assertNotIn("OverviewZoomController", BG_ROOT)
        self.assertNotIn("gnomeOverviewController", BG_ROOT)

        # GlobalStates overview transform bindings use overviewController directly
        self.assertIn('value: bgRoot.isGnomeLikeOverview ? overviewController.scale : 1.0', BG_ROOT)
        self.assertIn('value: bgRoot.isGnomeLikeOverview ? overviewController.scaleOriginX : 0.5', BG_ROOT)
        self.assertIn('value: bgRoot.isGnomeLikeOverview ? overviewController.scaleOriginY : 0.5', BG_ROOT)

        # WallpaperImage properties are fed from overviewController
        self.assertIn("scaleValue: overviewController ? overviewController.scale : 1.0", BG_ROOT)
        self.assertIn("scaleOriginX: overviewController ? overviewController.scaleOriginX : bgRoot.screen.width / 2", BG_ROOT)
        self.assertIn("scaleOriginY: overviewController ? overviewController.scaleOriginY : bgRoot.screen.height / 2", BG_ROOT)
        self.assertIn("scaleProgress: overviewController ? overviewController.scaleProgress : 0.0", BG_ROOT)

    def test_wallpaper_clip_radius_animates_from_overview_controller(self):
        """WallpaperImage smoothly derives clip radius from overviewController.cornerRadius."""
        self.assertIn("property real wallpaperClipRadius: overviewController ? overviewController.cornerRadius : 0", WALLPAPER_IMAGE)

    def test_overview_controller_gnome_preset_decreases_scale(self):
        """Gnome preset must shrink (zoom out < 1.0) and include followWidgetsScale."""
        self.assertIn("readonly property real gnomeTargetScale: Math.max(0.85, overviewCoverScale * 0.85)", OVERVIEW_BG_CONTROLLER)
        self.assertIn('readonly property bool followWidgetsScale: ["gnome", "camera-push", "depth", "card-lift"].indexOf(effectiveStyle) >= 0', OVERVIEW_BG_CONTROLLER)

    def test_overview_zoom_controller_fallback_does_not_force_magnification(self):
        """Legacy OverviewZoomController must not return 1.15 on zoomOutStyle 2."""
        self.assertNotIn("if (Config.options.background.zoomOutStyle === 2)", OVERVIEW_ZOOM_CONTROLLER)
        self.assertNotIn("return 1.15;", OVERVIEW_ZOOM_CONTROLLER)

    def test_gnome_window_handoff_owns_and_disables_one_named_rule(self):
        """Closing Overview must disable the same no_anim rule used to hide windows."""
        self.assertIn("quickshell-overview-window-handoff", OVERVIEW_WINDOW_TRANSITION)
        self.assertIn("_G.__ii_overview_window_handoff_rule", OVERVIEW_WINDOW_TRANSITION)
        self.assertIn("rule:set_enabled(true)", OVERVIEW_WINDOW_TRANSITION)
        self.assertIn("rule:set_enabled(false)", OVERVIEW_WINDOW_TRANSITION)
        self.assertIn(
            "Component.onDestruction: transitionScope.forceWindowHandoffInactive()",
            OVERVIEW_WINDOW_TRANSITION,
        )
        self.assertIn("id: windowHandoffProcess", OVERVIEW_WINDOW_TRANSITION)
        self.assertIn("if (windowHandoffProcess.running)", OVERVIEW_WINDOW_TRANSITION)
        self.assertIn("windowHandoffCommandQueued = true", OVERVIEW_WINDOW_TRANSITION)
        self.assertIn("transitionScope.runWindowHandoffCommand()", OVERVIEW_WINDOW_TRANSITION)
        self.assertIn("windowHandoffProcess.running = false;", OVERVIEW_WINDOW_TRANSITION)
        self.assertGreaterEqual(
            OVERVIEW_WINDOW_TRANSITION.count("transitionScope.setWindowHandoffActive(false)"),
            4,
        )

        # Entering the Gnome preset while Overview is already open must adopt
        # the live state before scheduling the handoff capture.
        self.assertIn("tRoot.isOverviewActive = true;", OVERVIEW_WINDOW_TRANSITION)

        # A second anonymous opacity rule restores visibility but leaves the
        # first rule's no_anim=true active for every future window.
        self.assertNotIn("opacity = '1.0 1.0'", OVERVIEW_WINDOW_TRANSITION)
        self.assertNotIn(
            "hl.window_rule({ match = { class = '.*' }, opacity = '0.0 0.0', no_anim = true })",
            OVERVIEW_WINDOW_TRANSITION,
        )


if __name__ == "__main__":
    unittest.main()
