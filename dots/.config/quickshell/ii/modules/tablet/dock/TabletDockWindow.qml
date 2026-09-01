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

/**
 * The tablet dock: Android's three navigation buttons in the corner, and the app row across
 * the bottom of the screen.
 *
 * No plate behind it. An Android tablet's home screen puts its icons straight onto the
 * wallpaper — the taskbar pill only appears over an app — so the dock here is a bare
 * full-width row and the icons carry their own contrast.
 *
 * Modelled on the Pixel Tablet taskbar rather than on modules/ii/dock. That is 6919 lines
 * of magnification, live previews, smart grouping, media/weather/sports widgets, drag
 * reordering and per-file context menus, every one of which assumes a cursor. What it does
 * share is the reveal rule, which is the right one: the app row belongs to an empty home
 * screen, and gets out of the way once something is running.
 */
PanelWindow {
    id: root

    readonly property string screenName: root.screen?.name ?? ""

    // ── Reveal ──────────────────────────────────────────────────────────────
    // Same rule as the ii dock: pinned always, otherwise only while this workspace has
    // nothing open. The navigation buttons are deliberately NOT part of this — they are
    // system controls, and a shell whose only way home disappears the moment you open
    // something is a shell you can get stuck in.
    property bool pinned: Config.options?.dock.pinnedOnStartup ?? false

    readonly property bool workspaceEmpty: {
        const workspaceId = HyprlandData.activeWorkspace?.id ?? -1;
        if (workspaceId === -1)
            return true;
        return HyprlandData.hyprlandClientsForWorkspace(workspaceId).length === 0;
    }

    readonly property bool anySidebarOpen: GlobalStates.effectiveLeftOpen || GlobalStates.effectiveRightOpen
    readonly property bool appsRevealed: root.pinned
        || (!root.anySidebarOpen && root.workspaceEmpty)

    // ── Apps ────────────────────────────────────────────────────────────────
    // The pins are the ones the ii dock uses. Sharing the list is deliberate: it is the
    // user's set of favourite apps, not a property of one shell's dock.
    readonly property var pinnedApps: Config.options?.dock?.pinnedApps ?? []

    /// Apps with a window open that are not already pinned, most recent last. Capped
    /// because the dock is a fixed strip, not a task list — recents is where everything
    /// open belongs.
    readonly property int maximumRecents: 3
    readonly property var recentApps: {
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

    // ── Navigation ──────────────────────────────────────────────────────────
    /// Android's back: leave whatever shell surface is on top. There is no generic
    /// "previous screen" for an arbitrary application, so this stops at the shell's own
    /// surfaces and is inert on a bare home screen, exactly as Android's back is.
    function navigateBack() {
        if (GlobalStates.tabletAppId.length > 0) {
            GlobalStates.closeTabletApp();
            return;
        }
        if (GlobalStates.appDrawerOpen) {
            GlobalStates.appDrawerOpen = false;
            return;
        }
        if (GlobalStates.recentsOpen) {
            GlobalStates.recentsOpen = false;
            return;
        }
        if (GlobalStates.dashboardPanelOpen) {
            GlobalStates.dashboardPanelOpen = false;
            return;
        }
        if (GlobalStates.sidebarLeftOpen)
            GlobalStates.sidebarLeftOpen = false;
    }

    /// Home: close whatever is open and land on an empty workspace, which is this family's
    /// home screen.
    function navigateHome() {
        GlobalStates.closeTabletApp();
        GlobalStates.appDrawerOpen = false;
        GlobalStates.recentsOpen = false;
        Hyprland.dispatch("hl.dsp.focus({ workspace = 'empty' })");
    }

    visible: Config.ready && !GlobalStates.screenLocked && !GlobalStates.appDrawerOpen

    anchors {
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    implicitHeight: dockColumn.implicitHeight + 20

    // Ignore, not Auto: the dock floats over the desktop the way Android's taskbar does,
    // rather than reserving a strip that every window then has to lay out around.
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:tabletDock"
    WlrLayershell.layer: WlrLayer.Top

    // Only the buttons take input. Without this the invisible full-width strip would
    // swallow taps meant for whatever is behind it — and unlike the old pill this row now
    // spans the whole screen, so the mask matters much more.
    mask: Region {
        regions: [navRegion, appsRegion]
    }

    Region {
        id: navRegion
        item: navRow
    }

    Region {
        id: appsRegion
        item: appRow
        // A hidden row must not keep taking input where it used to be.
        intersection: root.appsRevealed ? Intersection.Combine : Intersection.Subtract
    }

    // ── Page indicator ──────────────────────────────────────────────────────
    // Which home screen you are on. Only the workspaces on this monitor count: with a
    // second display, showing every workspace in the session would make the indicator
    // disagree with the swipe, which moves within the monitor.
    readonly property var monitorWorkspaces: {
        const list = [];
        for (const workspace of (Hyprland.workspaces?.values ?? [])) {
            // Special workspaces (scratchpad) have negative ids and are not pages.
            if (workspace && workspace.id > 0 && workspace.monitor?.name === root.screenName)
                list.push(workspace.id);
        }
        return list.sort((a, b) => a - b);
    }
    readonly property int activeWorkspaceId: {
        const monitor = Hyprland.monitors.values.find(m => m.name === root.screenName);
        return monitor?.activeWorkspace?.id ?? -1;
    }

    ColumnLayout {
        id: dockColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10
        spacing: 10

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 7
            visible: root.appsRevealed && root.monitorWorkspaces.length > 1
            opacity: root.appsRevealed ? 1 : 0

            Behavior on opacity {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            Repeater {
                model: root.monitorWorkspaces

                delegate: Rectangle {
                    required property int modelData
                    readonly property bool current: modelData === root.activeWorkspaceId

                    implicitWidth: current ? 18 : 6
                    implicitHeight: 6
                    radius: height / 2
                    color: "white"
                    opacity: current ? 0.95 : 0.45

                    Behavior on implicitWidth {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                }
            }
        }

        // The bottom line: navigation pinned to the corner, apps across the middle.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(navRow.implicitHeight, appRow.implicitHeight)

            RowLayout {
                id: navRow
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                TabletNavButton {
                    symbol: "arrow_back_ios_new"
                    symbolSize: 18
                    onActivated: root.navigateBack()
                }

                TabletNavButton {
                    // Android's home is a circle; the filled one reads as a button rather
                    // than as a status dot at this size.
                    symbol: "circle"
                    symbolSize: 15
                    onActivated: root.navigateHome()
                }

                TabletNavButton {
                    symbol: "square"
                    symbolSize: 15
                    onActivated: GlobalStates.toggleRecents(root.screenName)
                }
            }

            RowLayout {
                id: appRow
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                opacity: root.appsRevealed ? 1 : 0
                visible: opacity > 0.01
                transform: Translate {
                    y: (1 - appRow.opacity) * 24
                }

                Behavior on opacity {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(appRow)
                }

                Repeater {
                    model: root.pinnedApps

                    delegate: TabletDockButton {
                        required property string modelData
                        appId: modelData
                        iconSource: Quickshell.iconPath(TaskbarApps.getCachedIcon(modelData), "image-missing")
                        running: root.isRunning(modelData)
                        onActivated: root.launch(modelData)
                    }
                }

                // Divider, exactly as Android separates favourites from what is merely open.
                Rectangle {
                    visible: root.recentApps.length > 0
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: appRow.implicitHeight * 0.45
                    Layout.leftMargin: 4
                    Layout.rightMargin: 4
                    color: "white"
                    opacity: 0.3
                }

                Repeater {
                    model: root.recentApps

                    delegate: TabletDockButton {
                        required property string modelData
                        appId: modelData
                        iconSource: Quickshell.iconPath(TaskbarApps.getCachedIcon(modelData), "image-missing")
                        running: true
                        onActivated: root.launch(modelData)
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: appRow.implicitHeight * 0.45
                    Layout.leftMargin: 4
                    Layout.rightMargin: 4
                    color: "white"
                    opacity: 0.3
                }

                // The drawer is also a swipe up from the bottom edge; this is the same door
                // for anyone driving the shell with a pointer.
                TabletDockButton {
                    iconSize: 40
                    onActivated: GlobalStates.openAppDrawer(root.screenName)

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "apps"
                        iconSize: 26
                        color: "white"
                        style: Text.Outline
                        styleColor: Qt.rgba(0, 0, 0, 0.45)
                    }
                }
            }
        }
    }
}
