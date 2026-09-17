import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.editMode
import qs
import QtQuick

import "./widgets"

DockButton {
    id: root

    property var appToplevel: null
    property var dockContent: null
    property int delegateIndex: -1
    property int lastFocused: -1

    readonly property real dockHeight: Config.options?.dock.height ?? 60
    // The delegate wrapper owns the dock geometry. Keep the button on that
    // same slot so its indicator can sit outside the icon without shifting it.
    readonly property real slotWidth: root.dockContent?.buttonSlotSize ?? root.buttonSize
    readonly property real slotHeight: root.dockContent ? (root.isVertical ? root.dockContent.buttonSlotSize : root.dockContent.buttonSlotHeight) : root.buttonSize

    readonly property var desktopEntry: appToplevel ? TaskbarApps.getCachedDesktopEntry(appToplevel.appId) : null
    property bool isVertical: dockContent?.isVertical ?? false

    readonly property bool appIsActive: focusedWindowIndex >= 0

    /// Activation alone is not enough: Hyprland leaves it set on a window sent to another
    /// workspace with a silent move, which kept the dot lit under an app that had left
    /// the screen. It has to still be somewhere the user can see it.
    readonly property int focusedWindowIndex: {
        if (!appToplevel || !appToplevel.toplevels)
            return -1;
        for (let i = 0; i < appToplevel.toplevels.length; i++) {
            const toplevel = appToplevel.toplevels[i];
            if (toplevel?.activated && HyprlandData.toplevelOnScreen(toplevel))
                return i;
        }
        return -1;
    }

    readonly property bool appIsRunning: appToplevel && appToplevel.toplevels && appToplevel.toplevels.length > 0

    property bool _pressed: false

    readonly property real magScale: root.dockMagnificationScale

    transformOrigin: {
        let pos = root.dockPos;
        if (pos === "top")
            return Item.Top;
        if (pos === "left")
            return Item.Left;
        if (pos === "right")
            return Item.Right;
        return Item.Bottom;
    }

    readonly property string dockPos: dockContent?.dockPos ?? "bottom"
    readonly property string launchAnimation: Config.options?.dock?.launchAnimation ?? "bounce"
    readonly property string notificationAnimation: Config.options?.dock?.notificationAnimation ?? "bounce"

    transform: [attention.shift, attention.grow, attention.turn]

    DockAttentionAnimation {
        id: attention
        host: root
        dockPos: root.dockPos
    }

    function playLaunchAnimation() {
        attention.playLaunch(root.launchAnimation);
    }

    onAppIsRunningChanged: {
        if (appIsRunning)
            attention.settle();
    }

    property real pressProgress: _pressed ? 1 : 0
    scale: (1 - pressProgress * 0.12) * magScale
    Behavior on pressProgress {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }
    z: magScale > 1.01 ? Math.round(magScale * 100) : 1
    width: root.slotWidth
    height: root.slotHeight

    // Hover-only MouseArea for running apps (shows preview popup)
    Loader {
        id: hoverAreaLoader
        anchors.fill: parent
        active: true
        sourceComponent: MouseArea {
            id: hoverArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            cursorShape: Qt.PointingHandCursor
            onEntered: {
                if (dockContent?.suppressHover)
                    return;
                dockContent?.onButtonEntered(root);
                if (appIsRunning && appToplevel?.toplevels)
                    lastFocused = appToplevel.toplevels.length - 1;
            }
            onExited: {
                dockContent?.onButtonExited(root);
            }
        }
    }

    // ── Edit Mode: pinned, or merely here ────────────────────────────────────
    // A dock in the mode holds two kinds of icon - the ones that are KEPT and
    // the ones that are only open right now - and the only thing that told
    // them apart was the colour of a 16px badge, with the pinned one's badge
    // on the right and the unpinned one's on the left. Two neighbours put
    // their badges in the same gap, which read as one icon wearing both.
    //
    // So: the badges share a corner (one icon, one badge, never a pair in the
    // gap between two), a kept app gets a filled plate under it, and one that
    // is only open gets a dashed outline and a dimmed icon - the shape the
    // shell already uses for "a slot, not yet filled".
    readonly property bool editPinned: root.appToplevel?.pinned ?? false
    readonly property bool editBadgesActive: GlobalStates.editMode && (GlobalStates.editProgress > 0.85 || Appearance.reducedMotion)

    Loader {
        anchors.centerIn: parent
        z: -1
        active: root.editBadgesActive && (root.appToplevel?.appId ?? "") !== ""
        width: root.buttonSize
        height: root.buttonSize
        sourceComponent: Item {
            Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.normal
                visible: root.editPinned
                color: ColorUtils.transparentize(Appearance.colors.colPrimaryContainer, 0.45)
            }
            DashedBorder {
                anchors.fill: parent
                visible: !root.editPinned
                radius: Appearance.rounding.normal
                borderWidth: 1
                dashLength: 4
                gapLength: 3
                color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.6)
            }
        }
    }

    // Edit Mode: the unpin badge, with both stores it touches in one history
    // entry.
    Loader {
        anchors.top: parent.top
        anchors.right: parent.right
        z: 11
        active: root.editBadgesActive && root.editPinned
        sourceComponent: EditRemoveBadge {
            onClicked: {
                const appId = root.appToplevel?.appId ?? "";
                if (!appId)
                    return;
                const pinnedBefore = Array.from(Config.options.dock.pinnedApps ?? []);
                const orderBefore = Array.from(Config.options.dock.order ?? []);
                TaskbarApps.togglePin(appId);
                const pinnedAfter = Array.from(Config.options.dock.pinnedApps ?? []);
                const orderAfter = Array.from(Config.options.dock.order ?? []);
                GlobalStates.editHistoryPush({
                    "undo": () => { Config.options.dock.pinnedApps = pinnedBefore; Config.options.dock.order = orderBefore; },
                    "redo": () => { Config.options.dock.pinnedApps = pinnedAfter; Config.options.dock.order = orderAfter; }
                });
            }
        }
    }

    // Edit Mode: the other half of it. An app that is only open can be kept
    // from here, so the dock is arranged where it is drawn rather than only
    // from the catalogue.
    Loader {
        // The SAME corner as the badge above, deliberately: on opposite
        // corners two neighbouring icons put their badges together in the gap
        // between them, and the pair read as belonging to one icon.
        anchors.top: parent.top
        anchors.right: parent.right
        z: 11
        active: root.editBadgesActive && !root.editPinned
            && (root.appToplevel?.appId ?? "") !== ""
        sourceComponent: EditAddBadge {
            onClicked: {
                const appId = root.appToplevel?.appId ?? "";
                if (!appId)
                    return;
                const pinnedBefore = Array.from(Config.options.dock.pinnedApps ?? []);
                const orderBefore = Array.from(Config.options.dock.order ?? []);
                TaskbarApps.togglePin(appId);
                const pinnedAfter = Array.from(Config.options.dock.pinnedApps ?? []);
                const orderAfter = Array.from(Config.options.dock.order ?? []);
                GlobalStates.editHistoryPush({
                    "undo": () => { Config.options.dock.pinnedApps = pinnedBefore; Config.options.dock.order = orderBefore; },
                    "redo": () => { Config.options.dock.pinnedApps = pinnedAfter; Config.options.dock.order = orderAfter; }
                });
            }
        }
    }

    // Drag overlay (dots-hyprland pattern)
    Loader {
        anchors.fill: parent
        z: 10
        active: true
        sourceComponent: MouseArea {
            id: dragOverlay
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            property point pressPoint: Qt.point(0, 0)
            property int pressButton: Qt.NoButton
            property bool dragActive: false

            onPressed: event => {
                pressButton = event.button;
                root._pressed = event.button === Qt.LeftButton;
                // Local coordinates move under a stationary pointer as the
                // icon magnifies. Only scene movement can start a real drag.
                pressPoint = dragOverlay.mapToItem(null, event.x, event.y);
            }
            onPositionChanged: event => {
                if (!pressed || pressButton !== Qt.LeftButton)
                    return;
                const point = dragOverlay.mapToItem(null, event.x, event.y);
                const dist = Math.abs(root.isVertical ? point.y - pressPoint.y : point.x - pressPoint.x);
                // Only allow drag when delegateIndex >= 0 (reorderable items)
                if (!dragActive && dist > 5 && root.delegateIndex >= 0) {
                    dragActive = true;
                    root._pressed = false;
                    if (dockContent) {
                        dockContent.buttonHovered = false;
                        dockContent.startItemDrag(root.delegateIndex, dragOverlay, event.x, event.y);
                    }
                }
                if (dragActive) {
                    if (dockContent)
                        dockContent.moveItemDrag(dragOverlay, event.x, event.y);
                }
            }
            onReleased: event => {
                root._pressed = false;
                if (dragActive) {
                    dragActive = false;
                    if (dockContent)
                        dockContent.endItemDrag();
                    return;
                }
                // In Edit Mode a click is inert: the drag reorders, the badge
                // unpins, and nothing launches.
                if (GlobalStates.editMode)
                    return;
                if (event.button === Qt.RightButton) {
                    if (dockContent) {
                        dockContent.buttonHovered = false;
                        dockContent.lastHoveredButton = null;
                    }
                    dockContextMenu.open();
                    return;
                }
                if (event.button === Qt.MiddleButton) {
                    root.playLaunchAnimation();
                    root.desktopEntry?.execute();
                    return;
                }
                if (!appToplevel || appToplevel.toplevels.length === 0) {
                    root.playLaunchAnimation();
                    root.desktopEntry?.execute();
                    return;
                }
                lastFocused = (lastFocused + 1) % appToplevel.toplevels.length;
                appToplevel.toplevels[lastFocused].activate();
            }
            onCanceled: {
                root._pressed = false;
                if (dragActive) {
                    dragActive = false;
                    if (dockContent)
                        dockContent.cancelDrag();
                }
            }
        }
    }

    altAction: () => {
        if (dockContent) {
            dockContent.buttonHovered = false;
            dockContent.lastHoveredButton = null;
        }
        dockContextMenu.open();
    }

    DockContextMenu {
        id: dockContextMenu
        appToplevel: root.appToplevel
        desktopEntry: root.desktopEntry
        anchorItem: root
    }

    Connections {
        target: dockContextMenu
        function onActiveChanged() {
            if (!dockContent)
                return;
            if (dockContextMenu.active)
                dockContent.registerContextMenuOpen();
            else
                dockContent.registerContextMenuClose();
        }
    }

    Connections {
        target: Notifications
        function onNotify(notif) {
            if (!notif)
                return;
            var targetName = (root.desktopEntry?.name ?? root.appToplevel?.appId ?? "").toLowerCase();
            var appName = (notif.appName || "").toLowerCase();
            if (targetName !== "" && appName !== "" && (appName === targetName || targetName.includes(appName) || appName.includes(targetName))) {
                attention.playNotification(root.notificationAnimation);
            }
        }
    }

    // Safety: if this button is destroyed while menu is open, clean up the counter
    Component.onDestruction: {
        if (dockContent && dockContextMenu.active)
            dockContent.registerContextMenuClose();
    }

    DockAppIndicator {
        z: -1
    }
    DockAppIcon {
        z: 0
        anchors.centerIn: parent
        // Dimmed while the mode is on and the app is only open: the plate
        // behind a kept app and the weight of its icon say the same thing
        // twice, which is what makes the two groups readable at a glance.
        opacity: (GlobalStates.editMode && !root.editPinned) ? 0.55 : 1
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    Loader {
        id: tooltipLoader
        // A hidden PopupWindow still creates a native popup and its binding
        // tree for every app delegate. Load it only when the feature is
        // enabled or Edit Mode needs the labels for arrangement.
        active: (Config.options?.dock?.enableAppTooltip ?? false) || GlobalStates.editMode
        sourceComponent: DockTooltip {
            parentItem: root
            text: root.desktopEntry?.name ?? (root.appToplevel?.appId ?? "")
            // Always named while Edit Mode is on: several dock icons are a bare
            // glyph, and arranging them is easier when they say what they are.
            showTooltip: ((Config.options?.dock?.enableAppTooltip ?? false) || GlobalStates.editMode)
                && (hoverAreaLoader.item?.containsMouse ?? false)
        }
    }
}
