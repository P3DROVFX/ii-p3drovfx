#!/usr/bin/env python3
"""Static contract tests for the GNOME-style workspace overview in the Tablet App Drawer."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
OVERVIEW = "modules/tablet/appDrawer/TabletAppDrawerWorkspaceOverview.qml"


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


class TabletAppDrawerOverviewContractTests(unittest.TestCase):
    def test_config_option_is_opt_in(self):
        config = read("modules/common/Config.qml")
        self.assertIn("property bool showWorkspacesOverview: false", config)

    def test_settings_page_exposes_toggle(self):
        settings = read("modules/settings/configs/widgets/TabletAppDrawerConfig.qml")
        self.assertIn("showWorkspacesOverview", settings)
        self.assertIn("Show GNOME-style workspace overview", settings)

        overview_settings = read("modules/settings/configs/OverviewConfig.qml")
        self.assertIn("showWorkspacesOverview", overview_settings)
        self.assertIn("Show GNOME-style workspace overview", overview_settings)

    def test_app_drawer_embeds_workspace_overview_strip(self):
        content = read("modules/tablet/appDrawer/TabletAppDrawerContent.qml")
        wrapper = read("modules/tablet/appDrawer/TabletAppDrawer.qml")
        qmldir = read("modules/tablet/appDrawer/qmldir")

        self.assertIn("TabletAppDrawerWorkspaceOverview 1.0 TabletAppDrawerWorkspaceOverview.qml", qmldir)
        self.assertIn("property var screen: null", content)
        self.assertIn("screen: screenScope.modelData", wrapper)
        self.assertIn("TabletAppDrawerWorkspaceOverview {", content)
        self.assertIn("showWorkspacesOverview", content)

        # Overview must be placed after categoryStrip and before the app grid body
        cat_index = content.find("id: categoryStrip")
        overview_index = content.find("id: workspaceOverview")
        body_index = content.find("id: body")

        self.assertNotEqual(cat_index, -1)
        self.assertNotEqual(overview_index, -1)
        self.assertNotEqual(body_index, -1)
        self.assertGreater(overview_index, cat_index)
        self.assertLess(overview_index, body_index)

    def test_drawer_wires_bleed_and_keyboard(self):
        content = read("modules/tablet/appDrawer/TabletAppDrawerContent.qml")
        # Without it every Hyprland.dispatch in the strip's handlers is a silent ReferenceError.
        self.assertIn("import Quickshell.Hyprland\n", content)
        # The strip runs through the side margins so its edge fade meets the screen edge.
        self.assertIn("horizontalBleed: root.outerMargin", content)
        self.assertIn("Qt.Key_PageUp", content)
        self.assertIn("focusAdjacentWorkspace", content)

    def test_overview_component_contract(self):
        overview = read(OVERVIEW)

        self.assertIn("ScreencopyView", overview)
        self.assertIn("wallpaperPath", overview)
        self.assertIn("HyprlandData", overview)
        self.assertIn("workspaceSelected", overview)
        self.assertIn("windowSelected", overview)

        self.assertIn("hl.dsp.window.move", overview)
        self.assertIn("hl.dsp.window.swap", overview)
        self.assertIn("hl.dsp.window.close", overview)

    def test_empty_workspaces_stay_listed(self):
        overview = read(OVERVIEW)
        # Hyprland destroys a workspace when its last window leaves; the strip lists the
        # whole range plus the next free id, so cards never vanish or shift under a drop.
        self.assertIn("for (let id = first; id <= last; id++)", overview)
        self.assertIn("let next = last + 1;", overview)
        # Workspaces and windows are diffed, not rebuilt with every screencopy.
        self.assertIn("values: root.workspaceList", overview)
        self.assertIn('objectProp: "address"', overview)

    def test_cards_map_the_work_area(self):
        overview = read(OVERVIEW)
        # The bar's exclusive zone is not part of the thumbnail.
        self.assertIn("monitorData?.reserved", overview)
        self.assertIn("root.monitorScale", overview)

    def test_single_drag_path(self):
        overview = read(OVERVIEW)
        # One hit-tested drag path; the old DropArea/Drag pair fought it for the target.
        self.assertNotIn("DropArea", overview)
        self.assertNotIn("Drag.active", overview)
        self.assertIn("function hitTestWorkspace", overview)
        # Touch: swipe pans the strip, long press picks the window up.
        self.assertIn("Qt.MouseEventNotSynthesized", overview)
        self.assertIn("id: longPress", overview)
        self.assertIn("gradient: Gradient", overview)
        self.assertIn("Gradient.Horizontal", overview)


if __name__ == "__main__":
    unittest.main()
