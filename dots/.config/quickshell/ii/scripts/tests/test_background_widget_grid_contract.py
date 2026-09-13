#!/usr/bin/env python3
"""Contract test for background widget grid standardization (10px snap, spaced visual mesh)."""

import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent


class TestBackgroundWidgetGridContract(unittest.TestCase):

    def setUp(self):
        self.widget_canvas_path = REPO_ROOT / "modules" / "common" / "widgets" / "widgetCanvas" / "WidgetCanvas.qml"
        self.abstract_widget_path = REPO_ROOT / "modules" / "ii" / "background" / "widgets" / "AbstractBackgroundWidget.qml"
        self.bg_window_path = REPO_ROOT / "modules" / "ii" / "background" / "BackgroundWidgetsWindow.qml"
        self.config_path = REPO_ROOT / "modules" / "common" / "Config.qml"

        self.wallpaper_image_path = REPO_ROOT / "modules" / "ii" / "background" / "wallpaper" / "WallpaperImage.qml"

    def test_widget_canvas_defaults(self):
        content = self.widget_canvas_path.read_text()
        self.assertIn("property int alignmentGridStep: 10", content,
                      "WidgetCanvas should default alignmentGridStep to 10px")
        self.assertIn("property int visualGridStep: 40", content,
                      "WidgetCanvas should declare visualGridStep of 40px")
        self.assertIn("onVisualGridStepChanged: dotGrid.requestPaint()", content,
                      "WidgetCanvas should repaint dotGrid when visualGridStep changes")

    def test_widget_canvas_dotgrid_uses_visual_step(self):
        content = self.widget_canvas_path.read_text()
        self.assertIn("const step = Math.max(1, root.visualGridStep);", content,
                      "dotGrid onPaint should use root.visualGridStep rather than alignmentGridStep")

    def test_dot_size_and_circular_rendering(self):
        content = self.widget_canvas_path.read_text()
        self.assertIn("property real dotSize: 2.0", content,
                      "dotSize should stay small; 4.0 read as screen pollution")
        self.assertIn("ctx.arc(x, y, dotRadius, 0, tau);", content,
                      "dotGrid should render smooth circles using ctx.arc")

    def test_dotgrid_waits_for_settled_mode(self):
        """The lattice must not paint during the open animation.

        The desktop is shrink-scaled on every frame of it, and a full-screen
        Canvas FBO sampled along with that scale is the lag people see on open.
        """
        content = self.widget_canvas_path.read_text()
        self.assertIn("readonly property bool modeSettled", content,
                      "dotGrid should gate the mode on a settled transition")
        self.assertIn("root.editProgress >= 1", content,
                      "modeSettled should wait for the host's own progress scalar to land")
        self.assertIn("(root.editMode && modeSettled)", content,
                      "the mode half of `wanted` must be gated on modeSettled")

    def test_lattice_is_per_monitor(self):
        """A second monitor must not fade dots in for a shrink it never gets."""
        content = self.widget_canvas_path.read_text()
        self.assertIn("property real editProgress: 0", content,
                      "WidgetCanvas should take a per-monitor edit progress scalar")
        window = self.bg_window_path.read_text()
        self.assertIn("editMode: bgWidgetsWindow.isEditMonitor && GlobalStates.editMode", window,
                      "the desktop canvas should follow the mode only on the edited screen")
        self.assertIn("editProgress: bgWidgetsWindow.editProgress", window,
                      "the desktop canvas should be handed the per-monitor progress")

    def test_no_scale_written_during_drag(self):
        """A reposition must not touch `scale`.

        The 3% drag lift wrote root.scale on press and release, which
        re-rasterised every Canvas behind `Supersampled` and bumped the shared
        size map for a widget whose size never changed. The grab is reported by
        the snap guides and the selection halo instead.
        """
        content = self.abstract_widget_path.read_text()
        self.assertNotIn("dragLift", content,
                         "drag must not drive a scale factor")
        self.assertNotIn("isDragging ? 1.03", content,
                         "the press must not grow the widget")
        # The settled-scale rule that replaced it must stay settled: entry and
        # drag transients ride on `scale`, so re-registering per frame is the
        # churn that made the open animation cost main-thread work.
        self.assertIn("readonly property real settledScale", content,
                      "the size map should record the settled scale")
        self.assertIn("enabled: !root.exiting && root.entryProgress >= 1", content,
                      "entry must not stack a second animation on its own scalar")

    def test_wallpaper_drag_dim_reduced(self):
        content = self.wallpaper_image_path.read_text()
        self.assertIn("opacity: anyWidgetIsDragging ? 0.08 : 0.0", content,
                      "wallpaperDimLayer opacity during drag should be reduced to 0.08")

    def test_abstract_background_widget_grid_step(self):
        content = self.abstract_widget_path.read_text()
        self.assertIn("return Math.max(1, canvas ? canvas.alignmentGridStep : 10);", content,
                      "AbstractBackgroundWidget should fall back to 10px grid step")

    def test_background_widgets_window_explicit_grid(self):
        content = self.bg_window_path.read_text()
        self.assertIn("alignmentGridStep: 10", content,
                      "BackgroundWidgetsWindow widgetCanvas should explicitly set alignmentGridStep to 10")
        self.assertIn("visualGridStep: 40", content,
                      "BackgroundWidgetsWindow widgetCanvas should explicitly set visualGridStep to 40")

    def test_config_default_grid_step(self):
        content = self.config_path.read_text()
        self.assertIn("property int gridStep: 10", content,
                      "Config.qml background.widgets.gridStep should default to 10")


if __name__ == "__main__":
    unittest.main()
