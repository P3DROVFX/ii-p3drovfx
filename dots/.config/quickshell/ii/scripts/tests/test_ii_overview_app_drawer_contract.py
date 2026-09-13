#!/usr/bin/env python3
"""Static contracts for the ii family's optional App Drawer overview."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


class IiOverviewAppDrawerContractTests(unittest.TestCase):
    def test_preference_is_opt_in_and_exposed_at_the_end_of_overview_settings(self):
        config = read("modules/common/Config.qml")
        page = read("modules/settings/configs/OverviewConfig.qml")

        self.assertIn("property bool useAppDrawer: false", config)
        self.assertIn("Config.options.overview.useAppDrawer", page)
        self.assertIn("Change Overview to an App Drawer (Experimental)", page)
        self.assertGreater(page.rfind("useAppDrawer"), page.rfind('title: Translation.tr("Related settings")'))

    def test_ii_family_borrows_the_tablet_drawer_without_copying_it(self):
        family = read("panelFamilies/IllogicalImpulseFamily.qml")

        self.assertIn("import qs.modules.tablet.appDrawer", family)
        self.assertIn("component: TabletAppDrawer", family)
        self.assertIn("extraCondition: Config.options.overview.useAppDrawer", family)
        self.assertIn("toolHostComponent: appDrawerToolHost", family)
        self.assertIn("showTabletSystemApps: false", family)
        self.assertIn("allowHomeScreenPlacement: false", family)
        self.assertNotIn("TabletAppDrawerWindow {", family)
        self.assertNotIn("TabletAppDrawerContent {", family)

    def test_global_overview_route_selects_exactly_one_primary_surface(self):
        states = read("GlobalStates.qml")

        self.assertIn("readonly property bool overviewUsesAppDrawer: PanelFamily.isIi", states)
        self.assertIn("readonly property bool classicOverviewOpen: root.overviewOpen", states)
        self.assertIn("readonly property bool overviewSurfaceOpen: root.overviewUsesAppDrawer", states)
        for function_name in ("toggleOverview", "openOverview", "closeOverview"):
            self.assertIn(f"function {function_name}(", states)
        self.assertIn("root.toggleAppDrawer(monitorName)", states)
        self.assertIn("root.openAppDrawer(monitorName)", states)
        self.assertIn("root.toggleClassicOverview(monitorName)", states)
        self.assertIn("root.openClassicOverview(monitorName)", states)
        self.assertIn("if (root.overviewUsesAppDrawer) {", states)
        self.assertIn("root.overviewOpen !== root.appDrawerOpen", states)

        overview = read("modules/ii/overview/Overview.qml")
        self.assertIn("active: !GlobalStates.overviewUsesAppDrawer", overview)
        transition = read("modules/ii/overview/OverviewWindowTransition.qml")
        self.assertIn("!GlobalStates.overviewUsesAppDrawer &&", transition)

    def test_super_ipc_gestures_and_visible_entry_points_use_the_shared_route(self):
        overview = read("modules/ii/overview/Overview.qml")
        gestures = read("modules/common/TouchGestureActionRegistry.qml")

        ipc = overview.split('target: "search"', 1)[1].split("GlobalShortcut {", 1)[0]
        self.assertIn("GlobalStates.toggleOverview()", ipc)
        self.assertIn("GlobalStates.openOverview()", ipc)
        self.assertIn("GlobalStates.closeOverview()", ipc)
        self.assertIn('name: "searchToggleRelease"', overview)
        self.assertIn("GlobalStates.toggleOverview();", overview)
        self.assertIn('case "overview":\n            GlobalStates.toggleOverview(screenName);', gestures)

        for path in (
            "modules/ii/dock/DockContent.qml",
            "modules/ii/bar/widgets/workspaces/Workspaces.qml",
            "modules/ii/bar/widgets/workspaces/DockWorkspaces.qml",
            "modules/ii/background/widgets/utility/SearchPillWidget.qml",
            "modules/ii/background/widgets/utility/AndroidSearchBarWidget.qml",
        ):
            self.assertIn("GlobalStates.toggleOverview", read(path), path)

    def test_borrowed_drawer_removes_only_tablet_owned_actions(self):
        wrapper = read("modules/tablet/appDrawer/TabletAppDrawer.qml")
        content = read("modules/tablet/appDrawer/TabletAppDrawerContent.qml")

        self.assertIn("property bool showTabletSystemApps: true", wrapper)
        self.assertIn("property bool allowHomeScreenPlacement: true", wrapper)
        self.assertIn("!root.showTabletSystemApps ? []", content)
        self.assertIn("if (root.allowHomeScreenPlacement)", content)
        self.assertIn("toolHost.item.searchQuery = root.query", content)

    def test_search_intents_reach_the_borrowed_drawer_without_stale_classic_state(self):
        states = read("GlobalStates.qml")
        type_to_search = read("services/TypeToSearch.qml")
        ai_router = read("services/ai/AiSurfaceRouter.qml")
        drawer_window = read("modules/tablet/appDrawer/TabletAppDrawerWindow.qml")

        self.assertIn("property int appDrawerRequest: 0", states)
        self.assertIn("LauncherSearch.query = root.appDrawerQuery", states)
        self.assertIn("GlobalStates.appDrawerQuery = GlobalStates.appDrawerQuery + text", type_to_search)
        self.assertIn("GlobalStates.overviewSurfaceOpen", type_to_search)
        self.assertIn('GlobalStates.openSearchPanel("ai", monitorName, "")', ai_router)
        self.assertIn("function onAppDrawerRequestChanged()", drawer_window)
        self.assertIn("contentLoader.item?.setSearchQuery(GlobalStates.appDrawerQuery)", drawer_window)


if __name__ == "__main__":
    unittest.main()
