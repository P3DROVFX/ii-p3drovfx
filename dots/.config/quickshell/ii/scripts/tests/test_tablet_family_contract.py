#!/usr/bin/env python3
"""Static contracts for the tablet family's native-app and launcher boundaries."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


class TabletFamilyContractTests(unittest.TestCase):
    def test_hosted_system_apps_are_native_floating_windows_with_touch_navigation_chrome(self):
        window = read("modules/tablet/appWindow/TabletAppWindow.qml")

        self.assertIn("FloatingWindow {", window)
        self.assertNotIn("PanelWindow {", window)
        self.assertNotIn("WlrLayershell", window)
        self.assertNotIn("GlobalFocusGrab", window)
        self.assertIn('text: "arrow_back"', window)
        self.assertIn('text: "close"', window)
        self.assertIn("TabletNavigation.back()", window)
        self.assertIn("GlobalStates.closeTabletApp()", window)
        self.assertIn("onVisibleChanged", window)

    def test_only_one_native_system_app_host_is_created(self):
        hosts = read("modules/tablet/appWindow/TabletAppWindows.qml")

        self.assertIn("TabletAppWindow", hosts)
        self.assertNotIn("Variants", hosts)

    def test_cheatsheet_pages_are_hosted_as_native_apps(self):
        apps = read("modules/tablet/appWindow/TabletSystemApps.qml")
        family = read("panelFamilies/TabletFamily.qml")

        for app_id in ("timetable", "keybinds", "elements", "aminoAcids"):
            self.assertIn(f'id: "{app_id}"', apps)
            self.assertIn(f'"{app_id}":', family)
        self.assertNotIn('kind: "surface"', apps)
        self.assertNotIn("GlobalStates.openCheatsheet", apps)

    def test_reopening_drawer_never_leaves_a_closing_overlay_with_input(self):
        drawer = read("modules/tablet/appDrawer/TabletAppDrawerWindow.qml")

        self.assertIn("mask: Region", drawer)
        # Input while open or while being dragged open, never while closing. The drag case
        # was added when the sheet started following the finger; the closing case is the
        # original bug and must stay excluded.
        self.assertIn("root.wantOpen || TabletAppDrawerGestureController.tracking", drawer)
        self.assertIn("Intersection.Combine : Intersection.Subtract", drawer)

    def test_app_drawer_uses_one_progress_for_the_backdrop_sheet_and_dock_exit(self):
        drawer = read("modules/tablet/appDrawer/TabletAppDrawerWindow.qml")
        content = read("modules/tablet/appDrawer/TabletAppDrawerContent.qml")
        dock = read("modules/tablet/dock/TabletDockWindow.qml")

        self.assertIn("id: drawerViewport", drawer)
        self.assertIn("y: (1 - root.openProgress) * root.height", drawer)
        # The wash still rides the one progress. Which law it uses now depends on whether
        # the drawer is blurring at all; both branches are that same number.
        self.assertIn("opacity: root.useBlur ? root.openProgress * 0.72 : root.openProgress", drawer)
        self.assertIn("visible: !GlobalStates.screenLocked", drawer)
        self.assertNotIn("visible: (root.wantOpen || root.openProgress > 0.001)", drawer)
        self.assertIn("y: (1 - root.revealProgress) * root.searchHeight * 0.8", content)
        # One progress for both surfaces, which is what this test is named for: the dock
        # reads the drawer's controller rather than animating its own copy of the boolean.
        self.assertIn("drawerProgress: TabletAppDrawerGestureController.progress", dock)
        self.assertNotIn("property real drawerProgress: GlobalStates.appDrawerOpen ? 1 : 0", dock)
        # Negative: the dock rises with the sheet instead of dropping away from it.
        self.assertIn("y: -root.drawerProgress * root.dockContentHeight", dock)
        self.assertIn("&& root.drawerProgress < 0.999", dock)
        self.assertNotIn("!GlobalStates.appDrawerOpen || root.drawerProgress < 0.999", dock)

    def test_app_drawer_blurs_its_own_snapshot_so_the_blur_ramps_with_the_gesture(self):
        drawer = read("modules/tablet/appDrawer/TabletAppDrawerWindow.qml")

        # Compositor blur is a threshold here (the shell ships ignore_alpha), so it arrived
        # as a step part-way through the animation. The drawer blurs its own capture.
        self.assertIn("ScreencopyView", drawer)
        self.assertIn("blur: Math.min(1.0, root.openProgress * 1.15)", drawer)
        self.assertIn("live: false", drawer)
        # Transparency off means no capture, no blur, and a solid surface colour.
        self.assertIn("readonly property bool useBlur: Config.options?.appearance?.transparency?.enable", drawer)
        self.assertIn("captureSource: root.useBlur ? root.screen : null", drawer)
        self.assertIn("visible: root.useBlur && root.openProgress > 0.001", drawer)

    def test_dock_keeps_headroom_so_its_lift_is_not_clipped_by_its_own_surface(self):
        dock = read("modules/tablet/dock/TabletDockWindow.qml")

        # A layer surface has no overflow: without headroom the rising dock was cut off at
        # the surface's top edge a few pixels into the travel.
        self.assertIn("readonly property real liftHeadroom: root.dockContentHeight", dock)
        self.assertIn("implicitHeight: root.dockSurfaceHeight + root.liftHeadroom", dock)
        # Headroom is empty space to move through, never reserved work area.
        self.assertIn("exclusiveZone: root.reservesSpace ? root.dockSurfaceHeight : 0", dock)
        self.assertNotIn("exclusiveZone: root.reservesSpace ? root.implicitHeight : 0", dock)
        self.assertIn("anchors.bottom: parent.bottom", dock)

    def test_tablet_keybinds_route_to_tablet_surfaces_not_desktop_overlays(self):
        keybinds = read("modules/tablet/navigation/TabletSystemKeybinds.qml")
        states = read("GlobalStates.qml")

        for name in ("searchToggleRelease", "overviewWorkspacesToggle", "cheatsheetToggle", "usageToggle", "modesToggle"):
            self.assertIn(f'name: "{name}"', keybinds)
        self.assertIn("GlobalStates.toggleAppDrawer", keybinds)
        self.assertIn("GlobalStates.toggleTabletApp", keybinds)
        self.assertIn("workspace = 'empty'", states)
        self.assertIn("PanelFamily.nativeAppWindows", states)

    def test_legacy_left_sidebar_cannot_move_tablet_wallpaper(self):
        states = read("GlobalStates.qml")
        gestures = read("modules/common/TouchGestureActionRegistry.qml")

        self.assertIn("if (PanelFamily.nativeAppWindows)", states)
        self.assertIn('{ id: "sidebarLeft", name: "Left Sidebar", icon: "left_panel_open", families: ["ii", "waffle"] }', gestures)

    def test_tablet_dock_reuses_ii_context_menu_actions_with_pointer_and_touch_entrypoints(self):
        button = read("modules/tablet/dock/TabletDockButton.qml")
        menu = read("modules/tablet/dock/TabletDockContextMenu.qml")

        self.assertIn("import Quickshell.Wayland", button)
        self.assertIn("altAction: () => contextMenu.open()", button)
        self.assertIn("TabletDockContextMenu", button)
        for label in ("Launch", "Set as Live Preview", "Pin", "Close window"):
            self.assertIn(label, menu)
        self.assertIn("TaskbarApps.togglePin", menu)
        self.assertIn("toplevel.close()", menu)

    def test_tablet_navigation_is_a_spacious_pill_of_circular_touch_targets(self):
        dock = read("modules/tablet/dock/TabletDockWindow.qml")
        button = read("modules/tablet/dock/TabletNavButton.qml")

        self.assertIn("id: navigationPill", dock)
        self.assertIn("radius: Appearance.rounding.full", dock)
        self.assertIn("spacing: Appearance.sizes.elevationMargin * 1.25", dock)
        self.assertIn("navigationButtonSize: root.appButtonSize - Appearance.sizes.elevationMargin", dock)
        self.assertIn("implicitHeight: root.appButtonSize", dock)
        self.assertIn("buttonRadius: Appearance.rounding.full", button)
        self.assertIn("symbolSize: Math.round(root.navigationButtonSize * 0.625)", dock)


if __name__ == "__main__":
    unittest.main()
