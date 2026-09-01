pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The tablet dock: a floating pill at the bottom holding pinned apps, then the apps that
 * are actually open, then the button that opens the drawer.
 *
 * Modelled on the Pixel Tablet's taskbar rather than on the ii dock. The desktop dock is
 * 6919 lines of magnification, live previews, smart grouping, media/weather/sports widgets,
 * drag reordering and per-file context menus — all of it built for a cursor. None of that
 * is reused here; this is a new surface with the same job and a tenth of the surface area.
 */
PanelWindow {
    id: root

    readonly property string screenName: root.screen?.name ?? ""

    // The pins are the ones the ii dock uses. Sharing the list is deliberate: it is the
    // user's set of favourite apps, not a property of one shell's dock.
    readonly property var pinnedApps: Config.options?.dock?.pinnedApps ?? []

    /// Apps with a window open that are not already pinned, most recent last. Capped
    /// because the dock is a fixed strip, not a task list — the recents surface is where
    /// everything open belongs.
    readonly property int maximumRecents: 3
    readonly property var recentApps: {
        const pinnedNormalized = root.pinnedApps.map(id => TaskbarApps.normalizeAppId(id));
        const seen = [];
        for (const toplevel of (ToplevelManager.toplevels?.values ?? [])) {
            const appId = toplevel?.appId ?? "";
            if (!appId)
                continue;
            const normalized = TaskbarApps.normalizeAppId(appId);
            if (pinnedNormalized.indexOf(normalized) !== -1)
                continue;
            if (seen.indexOf(normalized) !== -1)
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
        const entry = TaskbarApps.getCachedDesktopEntry(appId);
        if (entry)
            entry.execute();
    }

    // The drawer covers the whole screen, so leaving the dock drawn under it would only
    // show through the scrim. The lock screen owns the display outright.
    visible: Config.ready && !GlobalStates.screenLocked && !GlobalStates.appDrawerOpen

    anchors {
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    implicitHeight: dockPill.implicitHeight + 24

    // Ignore, not Auto: the dock floats over the desktop the way Android's taskbar does,
    // rather than reserving a strip that every window then has to lay out around.
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:tabletDock"
    WlrLayershell.layer: WlrLayer.Top

    // Only the pill takes input. Without this the whole invisible full-width strip would
    // swallow taps meant for whatever is behind it.
    mask: Region {
        item: dockPill
    }

    Rectangle {
        id: dockPill
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12

        implicitWidth: dockRow.implicitWidth + 24
        implicitHeight: dockRow.implicitHeight + 12
        radius: height / 2
        color: Appearance.colors.colLayer1

        RowLayout {
            id: dockRow
            anchors.centerIn: parent
            spacing: 6

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
                Layout.preferredHeight: dockRow.implicitHeight * 0.5
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                color: Appearance.colors.colOnLayer1
                opacity: 0.18
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
                Layout.preferredHeight: dockRow.implicitHeight * 0.5
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                color: Appearance.colors.colOnLayer1
                opacity: 0.18
            }

            // The drawer is also a swipe up from the bottom edge; this is the same door for
            // anyone using a pointer, and a visible affordance that the drawer exists.
            TabletDockButton {
                id: allAppsButton
                iconSize: 40
                onActivated: GlobalStates.openAppDrawer(root.screenName)

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "apps"
                    iconSize: 26
                    color: Appearance.colors.colOnLayer1
                }
            }
        }
    }
}
