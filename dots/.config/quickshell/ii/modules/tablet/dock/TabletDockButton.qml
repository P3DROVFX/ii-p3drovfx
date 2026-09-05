import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.modules.common
import qs.modules.common.dock
import qs.modules.common.widgets
import qs.services

/**
 * One touch-sized item in the tablet dock: an adaptive app icon with a running dot.
 *
 * No hover growth and no tooltip — there is no cursor to read intent from, so the only
 * feedback available is the press itself.
 */
RippleButton {
    id: root

    property string appId: ""
    property bool running: false
    property real iconSize: 44
    property real buttonSize: root.iconSize + Appearance.sizes.elevationMargin * 2

    /**
     * Whether a tap on an app that is already open goes to that window.
     *
     * This button used to hand every tap to the host, which ran the .desktop entry — so
     * tapping an icon with a running dot under it started a second copy of the app instead
     * of going to the one the dot was reporting. A taskbar that does that is a taskbar the
     * dot lies on.
     */
    property bool preferFocus: true
    /// Milliseconds within which a second tap means "another window". 0 disables it.
    property int doubleTapWindowMs: 320

    /// Tapped, and this button has nothing of its own to do with it — the host launches.
    signal activated
    /// Deliberately asked for one more window of an app that is already running.
    signal newInstanceRequested

    implicitWidth: root.buttonSize
    implicitHeight: root.buttonSize
    buttonRadius: Appearance.rounding.full
    buttonRadiusPressed: Appearance.rounding.large
    colBackground: Appearance.colors.colLayer1
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colBackgroundActive: Appearance.colors.colLayer1Active
    colRipple: Appearance.colors.colLayer1Active
    releaseAction: () => root.handleTap()
    // RippleButton supplies both conventional right-click and the touch-first long hold;
    // the primary release is suppressed after a hold, so the app never launches behind its
    // own context menu.
    altAction: () => contextMenu.open()

    readonly property var appToplevels: {
        const normalized = TaskbarApps.normalizeAppId(root.appId);
        if (normalized.length === 0)
            return [];
        return Array.from(ToplevelManager.toplevels?.values ?? []).filter(toplevel =>
            TaskbarApps.normalizeAppId(toplevel?.appId ?? "") === normalized);
    }

    function _addressOf(toplevel) {
        const raw = String(toplevel?.HyprlandToplevel?.address ?? "").trim();
        if (raw.length === 0)
            return "";
        return raw.startsWith("0x") ? raw : `0x${raw}`;
    }

    /**
     * This app's windows, most recently used first.
     *
     * ToplevelManager lists windows in creation order and activating one does not move it,
     * so the order to switch along has to come from Hyprland's own focus stack — the same
     * `focusHistoryID` join Recents uses, for the same reason.
     */
    readonly property var orderedToplevels: {
        const focusOrder = {};
        for (const client of (HyprlandData.windowList ?? [])) {
            const raw = String(client?.address ?? "").trim();
            if (raw.length === 0)
                continue;
            focusOrder[raw.startsWith("0x") ? raw : `0x${raw}`] = Number(client?.focusHistoryID ?? 9999);
        }
        return root.appToplevels.slice().sort((left, right) =>
            (focusOrder[root._addressOf(left)] ?? 9999) - (focusOrder[root._addressOf(right)] ?? 9999));
    }

    property real _lastTapMs: 0

    function handleTap() {
        const now = Date.now();
        const isDouble = root.doubleTapWindowMs > 0 && root._lastTapMs > 0
            && (now - root._lastTapMs) <= root.doubleTapWindowMs;
        // A third tap starts a new pair rather than counting as a second double.
        root._lastTapMs = isDouble ? 0 : now;

        if (isDouble && root.appId.length > 0) {
            root.newInstanceRequested();
            return;
        }
        if (root.focusRunningWindow())
            return;
        root.activated();
    }

    /**
     * Go to this app's window, or to its next one if you are already in it.
     *
     * Returns false when there is nothing to go to, which is what makes a tap on a closed
     * app fall through to launching it.
     */
    function focusRunningWindow() {
        if (!root.preferFocus)
            return false;
        const windows = root.orderedToplevels;
        if (windows.length === 0)
            return false;
        // windows[0] is this app's most recent window. If that is the one already in front,
        // the tap means "the next one" — otherwise it means "this one".
        const alreadyHere = windows[0]?.activated ?? false;
        const target = (alreadyHere && windows.length > 1) ? windows[1] : windows[0];
        if (!target)
            return false;
        target.activate();
        return true;
    }

    DockIcon {
        id: icon
        anchors.centerIn: parent
        width: root.iconSize
        height: root.iconSize
        appId: root.appId
        isRunning: root.running
        visible: root.appId.length > 0
    }

    // Android marks a running app with a dot under the icon rather than a highlight behind
    // it, which keeps the adaptive icon itself as the visual focus.
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Appearance.sizes.elevationMargin / 8
        width: root.running && root.appId.length > 0 ? Appearance.sizes.elevationMargin * 0.625 : 0
        height: Appearance.sizes.elevationMargin * 0.625
        radius: height / 2
        color: Appearance.colors.colOnLayer1
        opacity: root.running && root.appId.length > 0 ? 0.85 : 0

        Behavior on width {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    TabletDockContextMenu {
        id: contextMenu
        anchorItem: root
        appId: root.appId
        appToplevels: root.appToplevels
    }
}
