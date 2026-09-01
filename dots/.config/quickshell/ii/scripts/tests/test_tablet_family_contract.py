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
        self.assertIn("root.wantOpen ? Intersection.Combine : Intersection.Subtract", drawer)

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
