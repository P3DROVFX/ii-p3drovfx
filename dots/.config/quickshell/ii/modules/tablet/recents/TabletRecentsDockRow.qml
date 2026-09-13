pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland

import qs
import qs.services
import qs.modules.common
import qs.modules.common.dock
import qs.modules.common.widgets

/**
 * The taskbar, drawn inside Recents.
 *
 * On a tablet Android keeps the taskbar visible in Overview, so the answer to "not this one
 * — something else" is one tap away instead of a trip back to the home screen. Here the real
 * dock is on the Top layer and Recents is an Overlay, so the dock is simply underneath and
 * cannot be reached at all. Raising the dock to Overlay would put it in competition with the
 * shade and the drawer, which are modal; drawing our own row is more code and less risk.
 *
 * Pinned apps only, deliberately. Android's taskbar also carries recent apps, but in this
 * surface those are the cards right above — listing them twice would be answering a question
 * the screen has already answered. What is missing from Recents is everything that is *not*
 * open, which is exactly what the pins are.
 *
 * No context menu on these, unlike the real dock's buttons: pinning and desktop actions are
 * dock business, and the menu is a PopupWindow that would fight this surface for the
 * exclusive keyboard focus it holds.
 */
Item {
    id: root

    /// Raised rather than called directly: anything that changes focus has to wait for this
    /// surface to unmap, and only the host knows when that is.
    signal launchRequested(var action)

    readonly property var pinnedApps: Config.options?.dock?.pinnedApps ?? []
    readonly property real iconSize: Math.max(Appearance.sizes.minimumTouchTarget - 4, 44)
    readonly property real buttonSize: root.iconSize + Appearance.sizes.elevationMargin * 2

    implicitHeight: root.pinnedApps.length > 0 ? row.implicitHeight : 0
    visible: root.pinnedApps.length > 0

    readonly property var runningNormalized: {
        const seen = [];
        for (const toplevel of (ToplevelManager.toplevels?.values ?? [])) {
            const appId = toplevel?.appId ?? "";
            if (appId.length === 0)
                continue;
            const normalized = TaskbarApps.normalizeAppId(appId);
            if (seen.indexOf(normalized) === -1)
                seen.push(normalized);
        }
        return seen;
    }

    function isRunning(appId) {
        return root.runningNormalized.indexOf(TaskbarApps.normalizeAppId(appId)) !== -1;
    }

    /// Raise what is already open rather than starting a second copy, which is what tapping
    /// a running app in a taskbar has always meant.
    function activate(appId) {
        const normalized = TaskbarApps.normalizeAppId(appId);
        const existing = Array.from(ToplevelManager.toplevels?.values ?? []).find(toplevel =>
            TaskbarApps.normalizeAppId(toplevel?.appId ?? "") === normalized);
        if (existing) {
            root.launchRequested(() => existing.activate());
            return;
        }
        root.launchRequested(() => TaskbarApps.getCachedDesktopEntry(appId)?.execute());
    }

    RowLayout {
        id: row
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Math.round(Appearance.sizes.elevationMargin * 0.6)

        Repeater {
            model: root.pinnedApps

            delegate: RippleButton {
                id: pinnedButton
                required property var modelData

                implicitWidth: root.buttonSize
                implicitHeight: root.buttonSize
                buttonRadius: Appearance.rounding.full
                buttonRadiusPressed: Appearance.rounding.large
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover
                colRipple: Appearance.colors.colLayer1Active

                releaseAction: () => root.activate(pinnedButton.modelData)

                DockIcon {
                    anchors.centerIn: parent
                    width: root.iconSize
                    height: root.iconSize
                    appId: pinnedButton.modelData
                    isRunning: root.isRunning(pinnedButton.modelData)
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Appearance.sizes.elevationMargin / 8
                    width: root.isRunning(pinnedButton.modelData) ? Appearance.sizes.elevationMargin * 0.625 : 0
                    height: Appearance.sizes.elevationMargin * 0.625
                    radius: height / 2
                    color: Appearance.colors.colOnLayer1
                    opacity: root.isRunning(pinnedButton.modelData) ? 0.85 : 0

                    Behavior on width {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }
            }
        }
    }
}
