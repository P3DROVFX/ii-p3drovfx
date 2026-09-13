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
        self.assertIn("readonly property bool holdsInput: root.wantOpen"
                      " || TabletAppDrawerGestureController.tracking", drawer)
        # Anything else leaves only the edge strip, so a closing overlay hands the rest of
        # the screen back in the same frame instead of eating the next tap on Apps.
        self.assertIn("item: root.holdsInput ? inputRegion : bottomEdgeCaptureStrip", drawer)

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
        # Transparency off means no capture, no blur, and a solid surface colour. The
        # capture is refused by the Loader rather than by a null captureSource: the view is
        # rebuilt per open anyway (see the comment in the file), so "do not build it" is
        # the same statement and one fewer state a stale frame could hide in.
        self.assertIn("readonly property bool useBlur: Config.options?.appearance?.transparency?.enable", drawer)
        self.assertIn("readonly property bool wantsBackdrop: root.useBlur", drawer)
        self.assertIn("active: root.wantsBackdrop && !GlobalStates.otherTabletOverlayOnScreen(root.overlayName)", drawer)
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

    def test_app_drawer_reorders_in_place_instead_of_rebuilding_the_grid(self):
        content = read("modules/tablet/appDrawer/TabletAppDrawerContent.qml")

        # Assigning a fresh array resets the view, and a reset fires no move transitions:
        # every tile is destroyed and rebuilt where it lands, which is the opposite of the
        # live reordering this is for.
        self.assertNotIn("model: root.gridEntries", content)
        self.assertIn("dynamicRoles: true", content)
        self.assertIn("gridModel.move(currentIndex, newIndex, 1)", content)
        self.assertIn("move: Transition", content)
        self.assertIn("displaced: Transition", content)
        # Entrance animates scale, never opacity: an interrupted opacity transition strands
        # a tile invisible, and a tile that never paints is worse than one that never moves.
        self.assertNotIn('property: "opacity"', content)

    def test_app_drawer_sorts_only_when_there_is_no_query(self):
        content = read("modules/tablet/appDrawer/TabletAppDrawerContent.qml")

        for mode in ('"nameDesc"', '"category"', '"usage"'):
            self.assertIn(mode, content)
        # With a query the ranking IS the order, and it is what moves under the user's
        # fingers as they type. Re-sorting it would throw that away.
        self.assertIn("if (q.length > 0)\n            return AppSearch.fuzzyQuery(q);", content)
        self.assertIn("readonly property var availableCategories", content)

    def test_long_press_offers_a_menu_instead_of_silently_adding_to_the_home_screen(self):
        content = read("modules/tablet/appDrawer/TabletAppDrawerContent.qml")
        menu = read("modules/tablet/menu/TabletInlineMenu.qml")
        tile = read("modules/tablet/appDrawer/TabletAppTile.qml")

        self.assertIn("root.openAppMenu(appTile, appCell.modelData.entry)", content)
        for label in ("Open", "Add to home screen", "Pin to dock"):
            self.assertIn(label, content)
        # Desktop-entry shortcuts, the way Android surfaces an app's own shortcuts.
        self.assertIn("entry.actions", content)
        # Drawn inside the drawer. A second surface would fight the drawer's exclusive
        # keyboard focus for something Android draws in the launcher itself.
        self.assertNotIn("PopupWindow {", menu)
        self.assertNotIn("HyprlandFocusGrab {", menu)
        # Touch-sized action surfaces with the shared dynamic-corner behavior, not bare
        # text rows. Pointer users reach the exact same path via right click.
        self.assertIn("useDynamicRadius: true", menu)
        # The rows themselves moved into the card every tablet menu is built from, so the
        # behaviour is asserted where it now lives; the drawer still opts into it above.
        card = read("modules/tablet/menu/TabletMenuCard.qml")
        self.assertIn("property bool useDynamicRadius: true", card)
        self.assertIn("buttonRadiusPressed: root.useDynamicRadius", card)
        self.assertIn("Appearance.colors.colError", card)
        self.assertIn("acceptedButtons: Qt.LeftButton | Qt.RightButton", tile)
        self.assertIn("if (event.button === Qt.RightButton)", tile)
        self.assertIn("root.contextRequested()", tile)
        self.assertIn("onContextRequested:", content)

    def test_tablet_quick_toggle_column_owns_vertical_scrolling_end_to_end(self):
        content = read("modules/tablet/sidebarDashboard/TabletDashboardContent.qml")
        panel = read("modules/common/quickToggles/AndroidQuickPanel.qml")

        self.assertIn("externalVerticalScroll: true", content)
        self.assertIn("contentHeight: Math.max(height,", content)
        self.assertIn("property bool externalVerticalScroll: false", panel)
        self.assertIn("interactive: !root.externalVerticalScroll && contentHeight > height", panel)
        self.assertIn("wheelEvent.accepted = false", panel)

    def test_compact_and_full_dashboard_widgets_coexist_as_tablet_quick_toggles(self):
        catalog = read("modules/common/quickToggles/androidStyle/QuickToggleCatalog.js")
        chooser = read("modules/common/quickToggles/androidStyle/AndroidToggleDelegateChooser.qml")
        compact_widget = read("modules/common/quickToggles/androidStyle/AndroidDashboardWidgetToggle.qml")
        full_widget = read("modules/common/quickToggles/androidStyle/AndroidFullDashboardWidgetToggle.qml")
        bottom_group = read("modules/ii/sidebarDashboard/BottomWidgetGroup.qml")
        tablet_content = read("modules/tablet/sidebarDashboard/TabletDashboardContent.qml")
        calendar_day = read("modules/common/dashboardWidgets/calendar/CalendarDayButton.qml")
        countdown = read("modules/common/dashboardWidgets/timer/CountdownTimer.qml")
        task_list = read("modules/common/dashboardWidgets/todo/TaskList.qml")

        for toggle_type in ("calendarWidget", "tasksWidget", "timerWidget",
                            "countdownWidget", "pomodoroWidget"):
            self.assertIn(f'{toggle_type}: {{ kind: "dashboardWidget"', catalog)
            self.assertIn(f'roleValue: "{toggle_type}"', chooser)
        for toggle_type in ("fullCalendarWidget", "fullTasksWidget", "fullTimerWidget",
                            "fullCountdownWidget", "fullPomodoroWidget"):
            self.assertIn(f'{toggle_type}: {{ kind: "fullDashboardWidget"', catalog)
            self.assertIn(f'roleValue: "{toggle_type}"', chooser)
        self.assertIn('allowedSizes: [[1, 2]], families: ["tablet"]', catalog)
        # The original summary cards keep their own visual implementation and stable IDs.
        self.assertIn("primaryValue", compact_widget)
        self.assertIn("id: widgetLayout", compact_widget)
        self.assertNotIn("dashboardWidgets.calendar", compact_widget)
        # Full ports are five additional types. The desktop bottom group consumes the
        # exact same common components, rather than a second implementation.
        for component in ("CalendarWidget", "TodoWidget", "Stopwatch",
                          "CountdownTimer", "PomodoroTimer"):
            self.assertIn(component, full_widget)
        for namespace in ("calendar", "todo", "timer"):
            common_import = f"qs.modules.common.dashboardWidgets.{namespace}"
            self.assertIn(common_import, full_widget)
            self.assertIn(common_import, bottom_group)
        self.assertIn("anchors.margins: root.scaled(6)", full_widget)
        self.assertIn("sourceComponent", bottom_group)
        self.assertIn("TimePickerPopup {", tablet_content)
        self.assertIn("function onCustomTimeRequested", tablet_content)
        self.assertIn("TimerService.setPomodoroTime", tablet_content)
        self.assertIn("PanelFamily.touchFirst ? Qt.LeftButton : Qt.NoButton", calendar_day)
        self.assertIn("button.compactCell ? 4 : 8", calendar_day)
        self.assertIn("root.countdowns.length === 0 && !root.dense", countdown)
        self.assertIn("taskListRoot.dense || cellHover.hovered", task_list)
        self.assertFalse((ROOT / "modules/ii/sidebarDashboard/calendar/CalendarWidget.qml").exists())
        self.assertFalse((ROOT / "modules/ii/sidebarDashboard/todo/TodoWidget.qml").exists())
        self.assertFalse((ROOT / "modules/ii/sidebarDashboard/pomodoro/PomodoroWidget.qml").exists())

    def test_dock_search_pill_is_configurable_and_delegates_what_its_buttons_do(self):
        bar = read("modules/tablet/dock/TabletDockSearchBar.qml")
        dock = read("modules/tablet/dock/TabletDockWindow.qml")
        states = read("GlobalStates.qml")

        self.assertIn('property string barStyle: "extended"', bar)
        self.assertIn("readonly property bool compact:", bar)
        # The bar knows how to draw an action and nothing about what one does, so a new
        # action is a line in the dock rather than a new dependency in the pill.
        self.assertIn("signal actionTriggered(string actionId)", bar)
        self.assertIn("function runSearchAction(actionId)", dock)
        self.assertIn("GlobalStates.openAppDrawerTool(root.screenName, id.substring(5))", dock)
        # A negative z is how an earlier version lost taps to the wrong handler; the
        # fallback area is ordered below the end buttons by declaration instead.
        self.assertNotIn("z: -1", bar)
        # Opening the drawer plainly must not reopen whatever panel was asked for last.
        self.assertIn('root.appDrawerTool = "";\n        root._showAppDrawer(monitorName);', states)

    def test_app_tile_geometry_does_not_depend_on_how_long_the_name_is(self):
        tile = read("modules/tablet/appDrawer/TabletAppTile.qml")

        # A layout let the label size the tile's contents, so a two-line name pushed its own
        # icon up and the whole row read as crooked.
        self.assertNotIn("ColumnLayout {", tile)
        self.assertIn("readonly property real labelHeight: Math.ceil(labelMetrics.height * 2)", tile)
        self.assertIn("height: root.labelHeight", tile)
        # Top-aligned in a fixed two-line box, and elided past that.
        self.assertIn("verticalAlignment: Text.AlignTop", tile)
        self.assertIn("elide: Text.ElideRight", tile)
        self.assertIn("maximumLineCount: 2", tile)

    def test_bottom_edge_has_a_pointer_target_so_a_pen_can_open_the_drawer(self):
        drawer = read("modules/tablet/appDrawer/TabletAppDrawerWindow.qml")

        # TouchGestureService reads evdev and only accepts devices it classifies as
        # touchscreens, so a pen arrives as a pointer and never reaches the drag registry.
        # The shade has had this strip on the top edge from the start.
        self.assertIn("id: bottomEdgeCaptureStrip", drawer)
        self.assertIn("id: bottomMouseDragArea", drawer)
        self.assertIn("preventStealing: true", drawer)
        # Upwards opens, so the sign is flipped against the shade's pull-down.
        self.assertIn("const travel = bottomMouseDragArea.startY - mouse.y;", drawer)
        self.assertIn("TabletAppDrawerGestureController.startTracking(root.screenName)", drawer)
        # Outside the sliding viewport: an area that moved with the sheet would read its own
        # coordinate shift as pointer movement and feed the gesture back into itself.
        self.assertLess(drawer.index("id: bottomEdgeCaptureStrip"), drawer.index("id: drawerViewport"))

    def test_navigation_buttons_use_androids_own_shapes(self):
        dock = read("modules/tablet/dock/TabletDockWindow.qml")

        # Chevron, circle, square — home was drawing the square and recents the circle.
        self.assertIn('if (action === "home")\n            return "radio_button_unchecked";', dock)
        self.assertIn('return "check_box_outline_blank";', dock)

    def test_app_grid_fades_at_the_bottom_instead_of_being_cut_off(self):
        content = read("modules/tablet/appDrawer/TabletAppDrawerContent.qml")

        self.assertIn("anchors.bottomMargin: 0", content)
        # An alpha mask, not a colour band. ScrollEdgeFade paints a colour, which ends
        # content only when the surface behind it is that colour; the drawer sits on a
        # blurred screencopy, so the band washed the last row without ever ending it.
        self.assertIn("layer.effect: OpacityMask {", content)
        self.assertIn("readonly property real fadeSize:", content)
        # Room to scroll the last row clear of the gradient.
        self.assertIn("bottomMargin: body.fadeSize", content)

    def test_dashboard_notification_controls_line_up_with_the_system_action_row(self):
        content = read("modules/tablet/sidebarDashboard/TabletDashboardContent.qml")
        notifications = read("modules/common/notifications/NotificationList.qml")

        # Notifications are read, not tapped, and were still drawn at the size the desktop's
        # 460px sidebar needs.
        self.assertIn("readonly property real notificationZoom:", content)
        self.assertNotIn("zoom: 1.12", content)
        # Both columns end on one line instead of the notification controls stopping short.
        self.assertIn("statusRowHeight: root.actionRowHeight", content)
        self.assertIn("property real statusRowHeight: 0", notifications)
        self.assertIn("baseHeight: root.statusRowHeight > 0", notifications)

    def test_dock_workspace_arrows_sit_at_the_extreme_ends(self):
        dock = read("modules/tablet/dock/TabletDockWindow.qml")

        self.assertIn("id: workspacePrevButton", dock)
        self.assertIn("id: workspaceNextButton", dock)
        # Everything else moves inwards to make room, rather than overlapping them.
        self.assertIn("anchors.left: root.workspaceArrowsRevealed"
                      " ? workspacePrevButton.right : parent.left", dock)
        self.assertIn("anchors.right: root.workspaceArrowsRevealed"
                      " ? workspaceNextButton.left : parent.right", dock)
        # The same dispatch the wallpaper swipe uses, so the two cannot disagree about
        # which way is "next".
        self.assertIn("hl.dsp.focus({ workspace = 'r+1' })", dock)
        self.assertIn("workspacePrevRegion", dock)

    def test_multi_finger_touch_swipes_replace_the_touchpads_scratchpad_bindings(self):
        service = read("services/TouchGestureService.qml")
        config = read("modules/common/Config.qml")
        registry = read("modules/common/TouchGestureActionRegistry.qml")

        # The hand's other fingers are not the active contact, so they have to be tracked
        # before the single-contact filter the edge recogniser runs on.
        self.assertIn("function multiCentroid()", service)
        self.assertIn("function multiEvaluate()", service)
        # Exactly the configured count: a further finger is a different gesture.
        self.assertIn("centroid.count !== root.multiFingerCount", service)
        # One action per hand-down, or a long swipe fires on every frame past the threshold.
        self.assertIn("root.multiFired = true;", service)
        # A binding this family cannot perform would commit and do nothing, which reads as
        # the touchscreen being broken rather than as a setting being wrong.
        self.assertIn("TouchGestureActionRegistry.availableForFamily(action, PanelFamily.current)", service)

        # The touchpad's three fingers do scratchpad in and scratchpad out. A tablet has no
        # touchpad and no use for a scratchpad; these are what a phone does instead.
        self.assertIn('property string swipeLeft: "workspaceNext"', config)
        self.assertIn('property string swipeRight: "workspacePrev"', config)
        self.assertIn('property string swipeUp: "appDrawer"', config)
        self.assertIn('property string swipeDown: "sidebarRight"', config)

        for action in ('id: "appDrawer"', 'id: "recents"', 'id: "home"',
                       'id: "workspaceNext"', 'id: "workspacePrev"'):
            self.assertIn(action, registry)

    def test_back_is_installed_by_the_family_that_knows_what_it_means(self):
        states = read("GlobalStates.qml")
        keybinds = read("modules/tablet/navigation/TabletSystemKeybinds.qml")
        registry = read("modules/common/TouchGestureActionRegistry.qml")

        self.assertIn("property var navigateBackHandler: null", states)
        self.assertIn("GlobalStates.navigateBackHandler = () => TabletNavigation.back()", keybinds)
        self.assertIn("if (GlobalStates.navigateBackHandler)", registry)
        # Shared code must not import a family to find out what back means there.
        self.assertNotIn("qs.modules.tablet", registry)

    def test_dock_fits_running_apps_to_the_space_and_groups_the_rest(self):
        dock = read("modules/tablet/dock/TabletDockWindow.qml")
        overflow = read("modules/tablet/dock/TabletDockOverflowButton.qml")
        menu = read("modules/tablet/dock/TabletDockOverflowMenu.qml")

        # A fixed three left most of a wide dock empty while hiding apps that had room.
        self.assertNotIn("readonly property int maximumRecents: 3", dock)
        self.assertIn("readonly property int automaticRecentsLimit:", dock)
        # The row is centred, so what bounds it is the wider flank, doubled.
        self.assertIn("return Math.max(left, right);", dock)
        self.assertIn("root.appRowSideReserve * 2", dock)

        # The group takes the last slot rather than being appended past it, so it holds the
        # app that would have been shown there plus everything opened since.
        self.assertIn("root.runningApps.slice(0, Math.max(0, root.recentSlots - 1))", dock)
        self.assertIn("root.runningApps.slice(Math.max(0, root.recentSlots - 1))", dock)
        self.assertIn("TabletDockOverflowButton {", dock)
        self.assertIn("readonly property var previewIds: root.appIds.slice(0, 4)", overflow)
        # Every app in the group is running by definition; re-running the launcher would
        # open a second copy of what the user was trying to get back to.
        self.assertIn("toplevel.activate()", menu)

    def test_every_tablet_menu_is_built_from_one_card(self):
        card = read("modules/tablet/menu/TabletMenuCard.qml")
        inline = read("modules/tablet/menu/TabletInlineMenu.qml")
        context = read("modules/tablet/dock/TabletDockContextMenu.qml")
        overflow = read("modules/tablet/dock/TabletDockOverflowMenu.qml")

        # Three menus with three radii, row heights and fonts meant the same gesture on two
        # icons a centimetre apart produced two visibly different menus, two of them at
        # desktop sizes on a surface meant for a fingertip.
        for menu in (inline, context, overflow):
            self.assertIn("TabletMenuCard {", menu)
        # Rows are the whole target, and a fingertip-exact row is one you mis-tap.
        self.assertIn("Math.max(Appearance.sizes.minimumTouchTarget + 8, 56)", card)
        self.assertIn("font.pixelSize: Appearance.font.pixelSize.normal", card)
        # A menu taller than the screen is a menu with unreachable entries.
        self.assertIn("property real maximumHeight: 0", card)
        self.assertIn("Flickable {", card)

    def test_tablet_family_loads_desktop_menu_and_edit_mode_with_touch_longpress(self):
        family = read("panelFamilies/TabletFamily.qml")
        self.assertIn("import qs.modules.ii.background.desktopMenu", family)
        self.assertIn("import qs.modules.ii.editMode", family)
        self.assertIn("component: DesktopMenu {}", family)
        self.assertIn("component: EditModeChrome {}", family)

        canvas = read("modules/common/widgets/widgetCanvas/WidgetCanvas.qml")
        self.assertIn("signal canvasLongPressed(real atX, real atY)", canvas)
        self.assertIn("canvasLongPressed(canvasLongPressHandler.point.position.x, canvasLongPressHandler.point.position.y)", canvas)

        bg_window = read("modules/ii/background/BackgroundWidgetsWindow.qml")
        self.assertIn("GlobalStates.openDesktopMenu(bgWidgetsWindow.editScreenName, p.x, p.y)", bg_window)
        self.assertIn("if (bgWidgetsWindow.canvasOverlay !== null)", bg_window)

        bg_root = read("modules/ii/background/BackgroundRoot.qml")
        self.assertIn("GlobalStates.openDesktopMenu(bgRoot.editScreenName, bgRootLongPress.point.position.x, bgRootLongPress.point.position.y)", bg_root)

        desktop_menu = read("modules/ii/background/desktopMenu/DesktopMenu.qml")
        self.assertIn("!PanelFamily.touchFirst", desktop_menu)

    def test_tablet_family_edit_mode_edits_tablet_dock_and_manages_home_screen_apps(self):
        tablet_page = read("modules/ii/editMode/EditTabletDockAppearancePage.qml")
        self.assertIn("Config.options.tablet.dock.height", tablet_page)
        self.assertIn("Config.options.tablet.dock.iconSize", tablet_page)
        self.assertIn("Config.options.tablet.dock.reserveSpace", tablet_page)
        self.assertIn("Config.options.tablet.dock.showSearchBar", tablet_page)
        self.assertIn("Config.options.tablet.dock.showNavigation", tablet_page)

        drawer = read("modules/ii/editMode/EditModeDrawer.qml")
        self.assertIn("PanelFamily.touchFirst ? tabletDockAppearancePage : dockAppearancePage", drawer)
        self.assertIn('if (root.section === "apps")', drawer)
        self.assertIn("id: appsListPage", drawer)
        self.assertIn("signal addAppRequested(string appId, real dropX, real dropY)", drawer)
        self.assertIn("signal toggleAppOnHomeScreenRequested(string appId)", drawer)

        chrome_content = read("modules/ii/editMode/EditModeChromeContent.qml")
        self.assertIn('section: "apps"', chrome_content)
        self.assertIn("drawerAddAppRequested", chrome_content)

        chrome_surface = read("modules/ii/editMode/EditModeChromeSurface.qml")
        self.assertIn("GlobalStates.addAppToHomeScreenHandler(appId, p.x, p.y)", chrome_surface)
        self.assertIn("GlobalStates.removeAppFromHomeScreenHandler(appId)", chrome_surface)

        family = read("panelFamilies/TabletFamily.qml")
        self.assertIn("GlobalStates.addAppToHomeScreenHandler =", family)
        self.assertIn("TabletHomeIcons.add(workspace, appId", family)
        self.assertIn("GlobalStates.removeAppFromHomeScreenHandler =", family)
        self.assertIn("GlobalStates.homeScreenAppsRevision++", family)

        desktop_menu_card = read("modules/ii/background/desktopMenu/DesktopMenuCard.qml")
        self.assertIn('GlobalStates.openEditCatalogue("apps"', desktop_menu_card)

    def test_bar_widgets_scale_their_insides_with_the_bar(self):
        appearance = read("modules/common/Appearance.qml")
        workspaces = read("modules/ii/bar/widgets/workspaces/Workspaces.qml")
        power = read("modules/ii/bar/widgets/power/ExpressivePowerButton.qml")
        policies = read("modules/ii/bar/widgets/policies/ExpressivePoliciesPanelButton.qml")
        classicPolicies = read("modules/ii/bar/widgets/policies/PoliciesPanelButton.qml")

        # One ratio for all of them, and 1.0 at the 40px default, so the desktop is unchanged.
        self.assertIn("readonly property real barContentScale:", appearance)
        self.assertIn("readonly property real barReferenceHeight: 40", appearance)

        # These sized the plate off the bar and left the glyph at its drawn size.
        self.assertIn("Math.round(22 * root.contentScale)", workspaces)
        self.assertIn("Math.round(26 * root.contentScale)", workspaces)
        self.assertIn("* root.contentScale)", power)
        self.assertIn("Math.round((root.vertical ? 28 : 22) * root.contentScale)", policies)
        # This one did not follow the bar even on the outside.
        self.assertNotIn("implicitWidth: 42", classicPolicies)
        self.assertIn("Math.round(42 * root.contentScale)", classicPolicies)

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
    def test_tablet_family_home_screen_supports_app_pairs_and_folders(self):
        icons = read("modules/tablet/homeScreen/TabletHomeIcons.qml")
        self.assertIn("function addPair(", icons)
        self.assertIn("function addFolder(", icons)
        self.assertIn("function combineIntoFolder(", icons)
        self.assertIn("function addAppToFolder(", icons)
        self.assertIn("function removeAppFromFolder(", icons)
        self.assertIn("function renameFolder(", icons)
        self.assertIn("function launchPair(", icons)

        qmldir = read("modules/tablet/homeScreen/qmldir")
        self.assertIn("TabletFolderDialog 1.0 TabletFolderDialog.qml", qmldir)

        layer = read("modules/tablet/homeScreen/TabletHomeIconsLayer.qml")
        self.assertIn('itemType === "pair"', layer)
        self.assertIn('itemType === "folder"', layer)
        self.assertIn("TabletHomeIcons.combineIntoFolder", layer)
        self.assertIn("TabletFolderDialog", layer)

        drawer = read("modules/ii/editMode/EditModeDrawer.qml")
        self.assertIn("signal addAppPairRequested(", drawer)
        self.assertIn("signal addFolderRequested(", drawer)
        self.assertIn("id: createPairPage", drawer)
        self.assertIn("id: createFolderPage", drawer)
        self.assertIn('buttonText: Translation.tr("Apps")', drawer)
        self.assertIn('root.openPage("createPair")', drawer)
        self.assertIn('root.openPage("createFolder")', drawer)

        states = read("GlobalStates.qml")
        self.assertIn("property var addAppPairToHomeScreenHandler: null", states)
        self.assertIn("property var addFolderToHomeScreenHandler: null", states)

        family = read("panelFamilies/TabletFamily.qml")
        self.assertIn("GlobalStates.addAppPairToHomeScreenHandler =", family)
        self.assertIn("GlobalStates.addFolderToHomeScreenHandler =", family)


if __name__ == "__main__":
    unittest.main()
