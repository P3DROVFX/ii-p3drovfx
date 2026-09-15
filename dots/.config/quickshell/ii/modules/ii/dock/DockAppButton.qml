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
            if (toplevel.activated && HyprlandData.toplevelOnScreen(toplevel))
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

    // ── App Launch Bounce Customization Tokens ──
    readonly property bool enableLaunchBounce: Config.options?.dock?.enableLaunchBounce ?? true
    readonly property real bounceHeight: Config.options?.dock?.bounceHeight ?? 18
    readonly property int bounceDuration: 280
    readonly property int maxBounceCycles: 3

    property real launchBounceY: 0
    readonly property string dockPos: dockContent?.dockPos ?? "bottom"

    readonly property real effectiveBounceOffset: {
        if (root.dockPos === "top")
            return -root.launchBounceY;
        if (root.dockPos === "left")
            return -root.launchBounceY;
        return root.launchBounceY;
    }

    transform: Translate {
        x: root.isVertical ? root.effectiveBounceOffset : 0
        y: !root.isVertical ? root.effectiveBounceOffset : 0
    }

    SequentialAnimation {
        id: launchBounceAnim
        loops: root.maxBounceCycles

        NumberAnimation {
            target: root
            property: "launchBounceY"
            from: 0
            to: -root.bounceHeight
            duration: Math.round(root.bounceDuration * 0.45)
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: root
            property: "launchBounceY"
            from: -root.bounceHeight
            to: 0
            duration: Math.round(root.bounceDuration * 0.55)
            easing.type: Easing.InQuad
        }
    }

    function triggerLaunchBounce() {
        if (!enableLaunchBounce)
            return;
        launchBounceAnim.stop();
        launchBounceY = 0;
        launchBounceAnim.start();
    }

    onAppIsRunningChanged: {
        if (appIsRunning && launchBounceAnim.running) {
            launchBounceAnim.loops = 1;
        }
    }

    scale: (_pressed ? 0.88 : 1.0) * magScale
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
            property real pressCoord: 0
            property bool dragActive: false

            onPressed: event => {
                root._pressed = true;
                if (event.button === Qt.LeftButton) {
                    pressCoord = root.isVertical ? event.y : event.x;
                }
            }
            onPositionChanged: event => {
                if (!pressed)
                    return;
                var cur = root.isVertical ? event.y : event.x;
                var dist = Math.abs(cur - pressCoord);
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
                    root.triggerLaunchBounce();
                    root.desktopEntry?.execute();
                    return;
                }
                if (!appToplevel || appToplevel.toplevels.length === 0) {
                    root.triggerLaunchBounce();
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
                root.triggerLaunchBounce();
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

    DockTooltip {
        text: root.desktopEntry?.name ?? (root.appToplevel?.appId ?? "")
        // Always named while Edit Mode is on: several dock icons are a bare
        // glyph, and arranging them is easier when they say what they are.
        showTooltip: ((Config.options?.dock?.enableAppTooltip ?? false) || GlobalStates.editMode)
            && (hoverAreaLoader.item?.containsMouse ?? false)
    }
}
