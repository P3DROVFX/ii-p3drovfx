pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

import qs
import qs.services
import qs.modules.common
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
    readonly property bool surfaceVisible: Config.ready && !GlobalStates.screenLocked
        && !GlobalStates.appDrawerOpen && root.dockRevealed
    readonly property bool reservesSpace: (root.tabletDock?.reserveSpace ?? true) && root.surfaceVisible

    readonly property real appIconSize: root.tabletDock?.iconSize ?? Appearance.sizes.minimumTouchTarget
    readonly property real appButtonSize: root.appIconSize + Appearance.sizes.elevationMargin * 2
    readonly property real pageIndicatorSize: Appearance.sizes.elevationMargin * 0.75

    // Favourite apps and adaptive icon treatment are deliberately shared with the ii dock:
    // they are personal launcher choices, not a desktop-family preference.
    readonly property var pinnedApps: Config.options?.dock?.pinnedApps ?? []
    readonly property int maximumRecents: 3
    readonly property bool showRunningApps: root.tabletDock?.showRunningApps ?? true
    readonly property bool showAppDrawerButton: root.tabletDock?.showAppDrawerButton ?? true
    readonly property bool showAppDividers: root.tabletDock?.showAppDividers ?? true

    readonly property var recentApps: {
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
        return seen.slice(-root.maximumRecents);
    }

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
        if (action === "home")
            return "check_box_outline_blank";
        return "radio_button_unchecked";
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

    visible: root.surfaceVisible

    anchors {
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    implicitHeight: root.pageCounterVisible || !root.compactWhenPageCounterHidden
        ? Math.max(root.tabletDock?.height ?? root.appButtonSize, root.dockContentHeight)
        : root.dockContentHeight

    // An explicit zone is used instead of ExclusionMode.Auto so the reserve follows the
    // tablet auto-hide state exactly. A hidden dock releases the work area in the same frame.
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: root.reservesSpace ? root.implicitHeight : 0
    WlrLayershell.namespace: "quickshell:tabletDock"
    WlrLayershell.layer: WlrLayer.Top

    // The transparent reserved strip must never swallow taps intended for an application.
    mask: Region {
        regions: [navigationRegion, appsRegion]
    }

    Region {
        id: navigationRegion
        item: navigationRow
        intersection: root.navigationRevealed ? Intersection.Combine : Intersection.Subtract
    }

    Region {
        id: appsRegion
        item: appRow
        intersection: root.appsRevealed ? Intersection.Combine : Intersection.Subtract
    }

    ColumnLayout {
        id: dockColumn
        anchors.fill: parent
        anchors.margins: Appearance.sizes.elevationMargin
        spacing: Appearance.sizes.elevationMargin / 2

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

            RowLayout {
                id: navigationRow
                anchors.right: parent.right
                anchors.rightMargin: Appearance.sizes.elevationMargin
                anchors.verticalCenter: parent.verticalCenter
                spacing: Appearance.sizes.elevationMargin / 2
                visible: root.navigationRevealed
                opacity: visible ? 1 : 0

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                Repeater {
                    model: root.navigationOrder

                    delegate: TabletNavButton {
                        required property string modelData
                        symbol: root.navigationSymbol(modelData)
                        buttonSize: root.appButtonSize
                        symbolSize: root.appIconSize * 0.625
                        onActivated: root.activateNavigation(modelData)
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

                Rectangle {
                    visible: root.showAppDividers && root.showAppDrawerButton
                        && (root.pinnedApps.length > 0 || root.recentApps.length > 0)
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
