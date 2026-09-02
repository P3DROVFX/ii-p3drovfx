pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

import qs
import qs.services
import qs.modules.common
import qs.modules.tablet.appDrawer
import qs.modules.common.widgets
import qs.modules.tablet.navigation

/**
 * Tablet taskbar: an Android-style launcher row with three-button navigation.
 *
 * Unlike its first overlay-only version, this is a real layer-shell reservation. Apps tile
 * above it instead of disappearing beneath it, while the user can still release that space
 * through the tablet-only auto-hide and reservation preferences.
 */
PanelWindow {
    id: root

    readonly property string screenName: root.screen?.name ?? ""
    readonly property var tabletDock: Config.options?.tablet?.dock
    readonly property bool pinned: Config.options?.dock?.pinnedOnStartup ?? false
    readonly property bool anySidebarOpen: GlobalStates.effectiveLeftOpen || GlobalStates.effectiveRightOpen

    readonly property bool workspaceEmpty: {
        const workspaceId = HyprlandData.activeWorkspace?.id ?? -1;
        if (workspaceId === -1)
            return true;
        return HyprlandData.hyprlandClientsForWorkspace(workspaceId).length === 0;
    }

    readonly property bool appRowEnabled: root.tabletDock?.showAppRow ?? true
    readonly property bool autoHideOnOccupiedWorkspace: root.tabletDock?.autoHideOnOccupiedWorkspace ?? true
    readonly property bool appsRevealed: root.appRowEnabled && (root.pinned || (!root.anySidebarOpen
        && (!root.autoHideOnOccupiedWorkspace || root.workspaceEmpty)))
    readonly property bool navigationEnabled: root.tabletDock?.showNavigation ?? true
    readonly property bool navigationRevealed: root.navigationEnabled
        && (root.appsRevealed || (root.tabletDock?.keepNavigationVisible ?? true))
    readonly property bool dockRevealed: root.appsRevealed || root.navigationRevealed
    // Keep the dock mapped long enough to leave the screen instead of unmapping it on the
    // first state change. The same structural clock drives opacity and translation below.
    // The same number the drawer uses, so the dock travels with the sheet instead of
    // animating its own copy of appDrawerOpen and finishing first.
    readonly property real drawerProgress: TabletAppDrawerGestureController.progress
    readonly property bool surfaceVisible: Config.ready && !GlobalStates.screenLocked
        && root.dockRevealed
    readonly property bool reservesSpace: (root.tabletDock?.reserveSpace ?? true) && root.surfaceVisible
        && root.drawerProgress < 0.999

    readonly property real appIconSize: root.tabletDock?.iconSize ?? Appearance.sizes.minimumTouchTarget
    readonly property real appButtonSize: root.appIconSize + Appearance.sizes.elevationMargin * 2
    // The pill itself matches an app item's full circular surface. Its three targets use the
    // remaining inner space, leaving only a compact shared inset around the cluster.
    readonly property real navigationButtonSize: root.appButtonSize - Appearance.sizes.elevationMargin
    readonly property real pageIndicatorSize: Appearance.sizes.elevationMargin * 0.75

    // Favourite apps and adaptive icon treatment are deliberately shared with the ii dock:
    // they are personal launcher choices, not a desktop-family preference.
    readonly property var pinnedApps: Config.options?.dock?.pinnedApps ?? []
    readonly property bool showRunningApps: root.tabletDock?.showRunningApps ?? true
    readonly property bool showAppDrawerButton: root.tabletDock?.showAppDrawerButton ?? true
    readonly property bool searchBarEnabled: root.tabletDock?.showSearchBar ?? true
    readonly property real searchBarWidth: root.tabletDock?.searchBarWidth ?? 320
    readonly property string searchBarStyle: root.tabletDock?.searchBarStyle ?? "extended"

    /// The dock decides what a search-bar button does; the bar only knows how to draw one.
    function runSearchAction(actionId) {
        const id = String(actionId ?? "");
        if (id === "none")
            return;
        if (id.startsWith("tool:")) {
            GlobalStates.openAppDrawerTool(root.screenName, id.substring(5));
            return;
        }
        // "apps" and "search" both land on the drawer; the difference is only which of its
        // two halves the user is reaching for, and the drawer focuses the field either way.
        GlobalStates.openAppDrawer(root.screenName);
    }
    // The search pill follows the app row: both belong to the home screen and both get out
    // of the way once something is running.
    readonly property bool searchRevealed: root.searchBarEnabled && root.appsRevealed
    readonly property bool showAppDividers: root.tabletDock?.showAppDividers ?? true
    // Tied to the dock as a whole rather than to the app row: moving between home screens
    // is useful exactly when something is open and the apps have got out of the way.
    readonly property bool workspaceArrowsRevealed: (root.tabletDock?.showWorkspaceArrows ?? true)
        && root.dockRevealed

    /// The same dispatch the wallpaper swipe uses, so the button and the gesture cannot
    /// disagree about which way is "next".
    function moveWorkspace(delta) {
        Hyprland.dispatch(delta > 0
            ? "hl.dsp.focus({ workspace = 'r+1' })"
            : "hl.dsp.focus({ workspace = 'r-1' })");
    }

    /// Everything running that is not already pinned, oldest first.
    readonly property var runningApps: {
        if (!root.showRunningApps)
            return [];
        const pinnedNormalized = root.pinnedApps.map(id => TaskbarApps.normalizeAppId(id));
        const seen = [];
        for (const toplevel of (ToplevelManager.toplevels?.values ?? [])) {
            const appId = toplevel?.appId ?? "";
            if (!appId)
                continue;
            const normalized = TaskbarApps.normalizeAppId(appId);
            if (pinnedNormalized.indexOf(normalized) !== -1 || seen.indexOf(normalized) !== -1)
                continue;
            seen.push(normalized);
        }
        return seen;
    }

    // ── How many running apps fit ───────────────────────────────────────────
    // The row is centred, so what bounds it is the wider of the two flanks, doubled. A
    // fixed count of three left most of a 1920px dock empty and hid apps that had room.
    readonly property real appSlotWidth: root.appButtonSize + Appearance.sizes.elevationMargin
    readonly property real dividerSlotWidth: root.showAppDividers
        ? Appearance.sizes.elevationMargin * 1.25 : 0

    readonly property real appRowSideReserve: {
        const margin = Appearance.sizes.elevationMargin;
        const arrow = root.workspaceArrowsRevealed ? root.appButtonSize + margin : 0;
        const left = arrow + (root.searchRevealed ? searchBar.width + margin : 0) + margin;
        const right = arrow + (root.navigationRevealed ? navigationPill.implicitWidth + margin : 0) + margin;
        return Math.max(left, right);
    }

    readonly property int automaticRecentsLimit: {
        let used = root.pinnedApps.length * root.appSlotWidth;
        if (root.pinnedApps.length > 0)
            used += root.dividerSlotWidth;
        if (root.showAppDrawerButton)
            used += root.appSlotWidth + root.dividerSlotWidth;
        const free = root.width - root.appRowSideReserve * 2 - used;
        return Math.max(0, Math.floor(free / root.appSlotWidth));
    }

    readonly property int configuredMaximumRecents: root.tabletDock?.maximumRecents ?? 0
    readonly property int recentSlots: root.configuredMaximumRecents > 0
        ? Math.min(root.configuredMaximumRecents, root.automaticRecentsLimit)
        : root.automaticRecentsLimit

    // The group takes the last slot rather than being appended past it, so it holds the app
    // that would have been shown there plus everything opened since. Dropping them instead
    // is what this replaces: the app was open and the dock gave no sign of it.
    readonly property bool recentsOverflowing: root.runningApps.length > root.recentSlots
    readonly property var recentApps: root.recentsOverflowing
        ? root.runningApps.slice(0, Math.max(0, root.recentSlots - 1))
        : root.runningApps
    readonly property var overflowApps: root.recentsOverflowing
        ? root.runningApps.slice(Math.max(0, root.recentSlots - 1))
        : []

    readonly property var runningNormalized: {
        const running = [];
        for (const toplevel of (ToplevelManager.toplevels?.values ?? [])) {
            const appId = toplevel?.appId ?? "";
            if (appId)
                running.push(TaskbarApps.normalizeAppId(appId));
        }
        return running;
    }

    function isRunning(appId) {
        return root.runningNormalized.indexOf(TaskbarApps.normalizeAppId(appId)) !== -1;
    }

    function launch(appId) {
        TaskbarApps.getCachedDesktopEntry(appId)?.execute();
    }

    readonly property var navigationOrder: {
        const configured = root.tabletDock?.navigationOrder ?? ["back", "home", "recents"];
        const accepted = ["back", "home", "recents"];
        const ordered = [];
        for (const action of configured) {
            if (accepted.indexOf(action) !== -1 && ordered.indexOf(action) === -1)
                ordered.push(action);
        }
        for (const action of accepted) {
            if (ordered.indexOf(action) === -1)
                ordered.push(action);
        }
        return ordered;
    }

    function navigationSymbol(action) {
        if (action === "back")
            return "arrow_back_ios_new";
        // Android's three buttons are chevron, circle, square, in that order. Home was
        // drawing the square and recents the circle, which is the pair swapped.
        if (action === "home")
            return "radio_button_unchecked";
        return "check_box_outline_blank";
    }

    function activateNavigation(action) {
        if (action === "back")
            TabletNavigation.back();
        else if (action === "home")
            TabletNavigation.home();
        else
            TabletNavigation.recents(root.screenName);
    }

    readonly property var monitorWorkspaces: {
        const list = [];
        for (const workspace of (Hyprland.workspaces?.values ?? [])) {
            if (workspace && workspace.id > 0 && workspace.monitor?.name === root.screenName)
                list.push(workspace.id);
        }
        return list.sort((a, b) => a - b);
    }
    readonly property int activeWorkspaceId: {
        const monitor = Hyprland.monitors.values.find(m => m.name === root.screenName);
        return monitor?.activeWorkspace?.id ?? -1;
    }
    readonly property bool pageCounterVisible: (root.tabletDock?.showPageCounter ?? true)
        && root.monitorWorkspaces.length > 1
        && (!(root.tabletDock?.hidePageCounterOnOccupiedWorkspace ?? true) || root.workspaceEmpty)
    readonly property bool compactWhenPageCounterHidden: root.tabletDock?.compactWhenPageCounterHidden ?? true
    readonly property real dockContentHeight: dockColumn.implicitHeight + Appearance.sizes.elevationMargin * 2
    /// What the dock actually occupies at rest, and therefore what it reserves.
    readonly property real dockSurfaceHeight: root.pageCounterVisible || !root.compactWhenPageCounterHidden
        ? Math.max(root.tabletDock?.height ?? root.appButtonSize, root.dockContentHeight)
        : root.dockContentHeight
    /// Empty, transparent space kept above the dock purely so it has somewhere to travel to.
    ///
    /// A layer surface has no overflow: anything translated past its top edge is cut off by
    /// the compositor, so the dock rising with the app drawer was being sliced off a few
    /// pixels in rather than lifting out of the screen. The headroom is masked out and
    /// outside the exclusive zone, so it costs nothing but the room to move.
    readonly property real liftHeadroom: root.dockContentHeight

    visible: root.surfaceVisible

    anchors {
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    implicitHeight: root.dockSurfaceHeight + root.liftHeadroom

    // An explicit zone is used instead of ExclusionMode.Auto so the reserve follows the
    // tablet auto-hide state exactly. A hidden dock releases the work area in the same frame.
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: root.reservesSpace ? root.dockSurfaceHeight : 0
    WlrLayershell.namespace: "quickshell:tabletDock"
    WlrLayershell.layer: WlrLayer.Top

    // The transparent reserved strip must never swallow taps intended for an application.
    mask: Region {
        regions: [navigationRegion, appsRegion, searchRegion, workspacePrevRegion, workspaceNextRegion]
    }

    Region {
        id: workspacePrevRegion
        item: workspacePrevButton
        intersection: root.workspaceArrowsRevealed ? Intersection.Combine : Intersection.Subtract
    }

    Region {
        id: workspaceNextRegion
        item: workspaceNextButton
        intersection: root.workspaceArrowsRevealed ? Intersection.Combine : Intersection.Subtract
    }

    Region {
        id: searchRegion
        item: searchBar
        intersection: root.searchRevealed ? Intersection.Combine : Intersection.Subtract
    }

    Region {
        id: navigationRegion
        item: navigationPill
        intersection: root.navigationRevealed ? Intersection.Combine : Intersection.Subtract
    }

    Region {
        id: appsRegion
        item: appRow
        intersection: root.appsRevealed ? Intersection.Combine : Intersection.Subtract
    }

    ColumnLayout {
        id: dockColumn
        // Bottom-anchored rather than filling: the surface is taller than the dock now, and
        // the extra height is headroom above it, not around it.
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Appearance.sizes.elevationMargin
        height: root.dockSurfaceHeight - Appearance.sizes.elevationMargin * 2
        spacing: Appearance.sizes.elevationMargin / 2
        // Rises with the sheet rather than dropping away from it: the drawer is pulled up
        // out of the dock, so the dock is part of what is being pulled.
        //
        // The fade is held back to the last stretch. Fading linearly made the dock vanish
        // while it was still on screen and still moving, which read as it being deleted
        // mid-gesture rather than travelling with the sheet.
        opacity: 1 - Math.max(0, (root.drawerProgress - 0.55) / 0.45)
        transform: Translate {
            y: -root.drawerProgress * root.dockContentHeight
        }

        Loader {
            id: pageCounterLoader
            Layout.alignment: Qt.AlignHCenter
            Layout.minimumHeight: 0
            Layout.preferredHeight: item?.implicitHeight ?? 0
            Layout.maximumHeight: Layout.preferredHeight
            active: root.pageCounterVisible

            sourceComponent: RowLayout {
                spacing: Appearance.sizes.elevationMargin * 0.875

                Repeater {
                    model: root.monitorWorkspaces

                    delegate: Rectangle {
                        required property int modelData
                        readonly property bool current: modelData === root.activeWorkspaceId

                        implicitWidth: current ? root.pageIndicatorSize * 3 : root.pageIndicatorSize
                        implicitHeight: root.pageIndicatorSize
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colOnLayer0
                        opacity: current ? 0.95 : 0.45

                        Behavior on implicitWidth {
                            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                        }
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.appButtonSize

            // Both arrows sit at the extreme ends, outside everything else: they are about
            // the screen you are on, not about what is on it.
            TabletNavButton {
                id: workspacePrevButton
                anchors.left: parent.left
                anchors.leftMargin: Appearance.sizes.elevationMargin
                anchors.verticalCenter: parent.verticalCenter
                visible: root.workspaceArrowsRevealed
                opacity: visible ? 1 : 0
                symbol: "chevron_left"
                buttonSize: root.appButtonSize
                symbolSize: Math.round(root.appButtonSize * 0.45)
                onActivated: root.moveWorkspace(-1)

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(workspacePrevButton)
                }
            }

            TabletNavButton {
                id: workspaceNextButton
                anchors.right: parent.right
                anchors.rightMargin: Appearance.sizes.elevationMargin
                anchors.verticalCenter: parent.verticalCenter
                visible: root.workspaceArrowsRevealed
                opacity: visible ? 1 : 0
                symbol: "chevron_right"
                buttonSize: root.appButtonSize
                symbolSize: Math.round(root.appButtonSize * 0.45)
                onActivated: root.moveWorkspace(1)

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(workspaceNextButton)
                }
            }

            TabletDockSearchBar {
                id: searchBar
                anchors.left: root.workspaceArrowsRevealed ? workspacePrevButton.right : parent.left
                anchors.leftMargin: Appearance.sizes.elevationMargin
                anchors.verticalCenter: parent.verticalCenter
                width: searchBar.compact
                    ? root.appButtonSize
                    : Math.min(root.searchBarWidth, parent.width * 0.3)
                barHeight: root.appButtonSize
                barStyle: root.searchBarStyle
                leadingAction: root.tabletDock?.searchLeadingAction ?? "search"
                trailingAction: root.tabletDock?.searchTrailingAction ?? "apps"
                placeholderText: root.tabletDock?.searchPlaceholder ?? ""
                visible: root.searchRevealed
                opacity: visible ? 1 : 0
                transform: Translate {
                    y: (1 - searchBar.opacity) * root.appButtonSize
                }

                Behavior on opacity {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(searchBar)
                }
                Behavior on width {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(searchBar)
                }

                onActivated: GlobalStates.openAppDrawer(root.screenName)
                onActionTriggered: actionId => root.runSearchAction(actionId)
            }

            Rectangle {
                id: navigationPill
                anchors.right: root.workspaceArrowsRevealed ? workspaceNextButton.left : parent.right
                anchors.rightMargin: Appearance.sizes.elevationMargin
                anchors.verticalCenter: parent.verticalCenter
                visible: root.navigationRevealed
                opacity: visible ? 1 : 0
                implicitWidth: navigationRow.implicitWidth + Appearance.sizes.elevationMargin
                implicitHeight: root.appButtonSize
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer1

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                RowLayout {
                    id: navigationRow
                    anchors.centerIn: parent
                    spacing: Appearance.sizes.elevationMargin * 1.25

                    Repeater {
                        model: root.navigationOrder

                        delegate: TabletNavButton {
                            required property string modelData
                            symbol: root.navigationSymbol(modelData)
                            buttonSize: root.navigationButtonSize
                            symbolSize: Math.round(root.navigationButtonSize * 0.625)
                            onActivated: root.activateNavigation(modelData)
                        }
                    }
                }
            }

            RowLayout {
                id: appRow
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: Appearance.sizes.elevationMargin
                visible: root.appsRevealed
                opacity: visible ? 1 : 0
                transform: Translate {
                    y: (1 - appRow.opacity) * root.appButtonSize
                }

                Behavior on opacity {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(appRow)
                }

                Repeater {
                    model: root.pinnedApps

                    delegate: TabletDockButton {
                        required property string modelData
                        appId: modelData
                        iconSize: root.appIconSize
                        buttonSize: root.appButtonSize
                        running: root.isRunning(modelData)
                        onActivated: root.launch(modelData)
                    }
                }

                Rectangle {
                    visible: root.showAppDividers && root.pinnedApps.length > 0 && root.recentApps.length > 0
                    Layout.preferredWidth: Appearance.sizes.elevationMargin / 8
                    Layout.preferredHeight: root.appButtonSize * 0.45
                    Layout.leftMargin: Appearance.sizes.elevationMargin / 2
                    Layout.rightMargin: Appearance.sizes.elevationMargin / 2
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.3
                }

                Repeater {
                    model: root.recentApps

                    delegate: TabletDockButton {
                        required property string modelData
                        appId: modelData
                        iconSize: root.appIconSize
                        buttonSize: root.appButtonSize
                        running: true
                        onActivated: root.launch(modelData)
                    }
                }

                TabletDockOverflowButton {
                    id: overflowButton
                    visible: root.recentsOverflowing && root.overflowApps.length > 0
                    appIds: root.overflowApps
                    iconSize: root.appIconSize
                    buttonSize: root.appButtonSize
                    onActivated: overflowMenu.open()

                    TabletDockOverflowMenu {
                        id: overflowMenu
                        anchorItem: overflowButton
                        appIds: root.overflowApps
                    }
                }

                Rectangle {
                    visible: root.showAppDividers && root.showAppDrawerButton
                        && (root.pinnedApps.length > 0 || root.recentApps.length > 0
                            || root.recentsOverflowing)
                    Layout.preferredWidth: Appearance.sizes.elevationMargin / 8
                    Layout.preferredHeight: root.appButtonSize * 0.45
                    Layout.leftMargin: Appearance.sizes.elevationMargin / 2
                    Layout.rightMargin: Appearance.sizes.elevationMargin / 2
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.3
                }

                TabletDockButton {
                    visible: root.showAppDrawerButton
                    iconSize: root.appIconSize
                    buttonSize: root.appButtonSize
                    onActivated: TabletNavigation.appDrawer(root.screenName)

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "apps"
                        iconSize: root.appIconSize * 0.625
                        fill: 1
                        color: Appearance.colors.colOnLayer0
                        style: Text.Outline
                        styleColor: Appearance.colors.colLayer0
                    }
                }
            }
        }
    }
}
