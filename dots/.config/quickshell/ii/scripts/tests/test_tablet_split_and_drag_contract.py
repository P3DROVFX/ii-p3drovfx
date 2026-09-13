#!/usr/bin/env python3
"""Static contract tests for the tablet family's split handles and drag-to-launch."""

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


class SplitHandlesContract(unittest.TestCase):
    def test_registered_only_in_the_tablet_family(self):
        self.assertIn("TabletSplitHandles 1.0 TabletSplitHandles.qml", read("modules/tablet/windows/qmldir"))
        self.assertIn("PanelLoader { component: TabletSplitHandles {} }", read("panelFamilies/TabletFamily.qml"))
        self.assertNotIn("TabletSplitHandles", read("panelFamilies/IllogicalImpulseFamily.qml"))

    def test_config_and_settings(self):
        config = read("modules/common/Config.qml")
        self.assertIn("property bool splitHandles: true", config)
        self.assertIn("property int splitHandleWidth: 12", config)
        settings = read("modules/settings/configs/widgets/TabletWindowsConfig.qml")
        self.assertIn("Config.options.tablet.windows.splitHandles = checked", settings)
        self.assertIn("Config.options.tablet.windows.splitHandleWidth = value", settings)

    def test_hyprland_leaves_the_gutter(self):
        appearance = read("modules/common/Appearance.qml")
        self.assertIn("readonly property int effectiveGapsIn:", appearance)
        self.assertIn("PanelFamily.isTablet", appearance)
        # Both places that push gaps_in must push the effective value.
        pushes = re.findall(r"gaps_in = '\" \+ ([\w.]+) \+", appearance)
        self.assertTrue(pushes)
        self.assertTrue(all(p == "root.effectiveGapsIn" for p in pushes), pushes)

    def test_resizes_the_first_side_and_swaps_by_address(self):
        handles = read("modules/tablet/windows/TabletSplitHandles.qml")
        self.assertIn("SplitGeometry.resizePlan", handles)
        self.assertIn("hl.dsp.window.swap", handles)
        self.assertIn("TabletWindowActions.setFloating", handles)
        self.assertIn("TabletWindowActions.closeWindow", handles)
        self.assertIn('objectProp: "key"', handles)

    def test_only_the_pill_is_drawn(self):
        handles = read("modules/tablet/windows/TabletSplitHandles.qml")
        # The gutter keeps the wallpaper; the old filled bar is gone.
        self.assertNotIn("id: bar", handles)
        self.assertIn("component Pill: Rectangle", handles)

    def test_pill_has_air_on_both_sides(self):
        config = read("modules/common/Config.qml")
        self.assertIn("property int splitHandleSpacing: 4", config)
        appearance = read("modules/common/Appearance.qml")
        self.assertIn("splitHandleSpacing", appearance[appearance.index("readonly property int effectiveGapsIn:"):])
        handles = read("modules/tablet/windows/TabletSplitHandles.qml")
        # Centred in the gutter at its own width, not stretched to the gutter's.
        self.assertIn("(divider.thickness - handlesWindow.pillThickness) / 2", handles)

    def test_floating_windows_cover_the_pill(self):
        handles = read("modules/tablet/windows/TabletSplitHandles.qml")
        self.assertIn("intersection: Intersection.Subtract", handles)
        self.assertIn("readonly property bool occluded:", handles)
        self.assertIn("enabled: !handle.occluded", handles)

    def test_pills_follow_hyprlands_workspace_slide(self):
        handles = read("modules/tablet/windows/TabletSplitHandles.qml")
        # A layer surface does not move with the workspace animation, so it copies it.
        self.assertIn("hyprctl -j animations", handles)
        self.assertIn("Easing.BezierSpline", handles)
        self.assertIn("Hyprland.monitorFor(handlesWindow.screen)?.activeWorkspace?.id", handles)
        self.assertIn("outgoingDividers", handles)


class DragToLaunchContract(unittest.TestCase):
    def test_config_and_settings(self):
        config = read("modules/common/Config.qml")
        self.assertIn("property bool dragToLaunch: true", config)
        self.assertIn("property int edgeSwitchDelay: 600", config)
        settings = read("modules/settings/configs/widgets/TabletAppDrawerConfig.qml")
        self.assertIn("Config.options.tablet.appDrawer.dragToLaunch = checked", settings)

    def test_only_the_tablet_family_drags(self):
        self.assertIn("allowDragToLaunch: false", read("panelFamilies/IllogicalImpulseFamily.qml"))
        self.assertIn("allowDragToLaunch: root.allowDragToLaunch", read("modules/tablet/appDrawer/TabletAppDrawer.qml"))

    def test_drawer_keeps_input_and_fades_with_opacity(self):
        window = read("modules/tablet/appDrawer/TabletAppDrawerWindow.qml")
        self.assertIn("|| dragLaunch.active", window)
        self.assertIn("opacity: 1 - dragLaunch.fade", window)
        self.assertIn("contentLoader.item.appDragEnded.connect(dragLaunch.end)", window)
        # One handler per signal: a second onOpenProgressChanged blanked the whole drawer.
        self.assertEqual(window.count("onOpenProgressChanged:"), 1)

    def test_page_turn_is_virtual_until_the_drop(self):
        overlay = read("modules/tablet/appDrawer/TabletAppDragLaunchOverlay.qml")
        turn = overlay[overlay.index("function turnPage()"):overlay.index("// ── Gesture")]
        # Switching the real workspace mid-drag ended a mouse drag; only the drop switches.
        self.assertNotIn("Hyprland.dispatch", turn)
        drop = overlay[overlay.index("function end("):overlay.index("function resetFade()")]
        self.assertIn("hl.dsp.focus({ workspace = ${pending.target} })", drop)
        self.assertIn('hl.dsp.layout("preselect ${plan.direction}")', drop)

    def test_keyboard_is_released_only_after_the_drop(self):
        # Releasing focus mid-drag is a focus change, and a focus change ends a held mouse
        # drag; keeping it until the drop makes Hyprland refuse to focus the split target.
        window = read("modules/tablet/appDrawer/TabletAppDrawerWindow.qml")
        self.assertIn("!dragLaunch.releasingKeyboard", window)
        self.assertNotIn("!dragLaunch.active && dragLaunch.fade", window)
        overlay = read("modules/tablet/appDrawer/TabletAppDragLaunchOverlay.qml")
        drop = overlay[overlay.index("function end("):overlay.index("function commitDrop(")]
        self.assertIn("root.releasingKeyboard = true", drop)
        self.assertIn("placementTimer.restart()", drop)

    def test_tile_prevents_stealing_only_after_the_hold(self):
        tile = read("modules/tablet/appDrawer/TabletAppTile.qml")
        self.assertIn("preventStealing: root.dragEnabled && holdTimer.fired", tile)


class NoBordersContract(unittest.TestCase):
    """AGENTS.md: never use border in designs."""

    FILES = [
        "modules/tablet/appDrawer/TabletAppDragLaunchOverlay.qml",
        "modules/tablet/appDrawer/TabletAppDrawerWorkspaceOverview.qml",
        "modules/tablet/windows/TabletSplitHandles.qml",
    ]

    def test_new_surfaces_have_no_borders(self):
        for path in self.FILES:
            with self.subTest(path=path):
                self.assertIsNone(re.search(r"\bborder\.(width|color)\s*:", read(path)))


if __name__ == "__main__":
    unittest.main()
