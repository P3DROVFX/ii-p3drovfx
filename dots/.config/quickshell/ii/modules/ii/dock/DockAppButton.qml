import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.dock
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

    /** The notification animation alone, for the Settings preview. */
    function playNotificationAnimation() {
        attention.playNotification(root.notificationAnimation);
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
    // Two tiers only (see the delegate wrapper's z): the proportional form
    // re-ordered the render stack on every frame the lens moved.
    z: magScale > 1.01 ? 2 : 1
    width: root.slotWidth
    height: root.slotHeight

    // Unified hover + click + drag MouseArea (replaces two Loader { active: true } MouseAreas)
    MouseArea {
        id: interactionArea
        anchors.fill: parent
        z: 10
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        property point pressPoint: Qt.point(0, 0)
        property int pressButton: Qt.NoButton
        property bool dragActive: false

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
        onPressed: event => {
            pressButton = event.button;
            root._pressed = event.button === Qt.LeftButton;
            // Local coordinates move under a stationary pointer as the
            // icon magnifies. Only scene movement can start a real drag.
            pressPoint = interactionArea.mapToItem(null, event.x, event.y);
        }
        onPositionChanged: event => {
            if (!pressed || pressButton !== Qt.LeftButton)
                return;
            const point = interactionArea.mapToItem(null, event.x, event.y);
            const dist = Math.max(Math.abs(point.x - pressPoint.x), Math.abs(point.y - pressPoint.y));
            // Only allow drag when delegateIndex >= 0 (reorderable items)
            if (!dragActive && dist > 5 && root.delegateIndex >= 0) {
                dragActive = true;
                root._pressed = false;
                if (dockContent) {
                    dockContent.buttonHovered = false;
                    dockContent.startItemDrag(root.delegateIndex, interactionArea, event.x, event.y);
                }
            }
            if (dragActive) {
                if (dockContent)
                    dockContent.moveItemDrag(interactionArea, event.x, event.y);
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
                dockContent?.openAppContextMenu(root, root.appToplevel, root.desktopEntry);
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

    // ── Edit Mode: pinned, or merely here ────────────────────────────────────
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

    altAction: () => {
        dockContent?.openAppContextMenu(root, root.appToplevel, root.desktopEntry);
    }

    Component.onCompleted: dockContent?.registerAppButton(root)
    Component.onDestruction: dockContent?.unregisterAppButton(root)

    DockRunningIndicator {
        // Above the plate: the shape mask covers the bottom of the slot and used
        // to cut the indicator in half.
        z: 1
        toplevels: root.appToplevel?.toplevels ?? []
        // Reuses the dock's filter for a window Hyprland left activated after
        // a silent move to another workspace.
        focusedIndex: root.focusedWindowIndex
        edge: root.dockPos
        edgeExtent: (root.isVertical ? root.slotHeight : root.slotWidth) * 0.8
        scaleFactor: root.dockHeight / 56
        margin: Math.max(1, (root.dockContent?.dotMarginV ?? 1) * 0.35)
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
        // A tooltip is a native popup window, and this is the dock's most
        // numerous delegate: one per app meant one popup per icon for the whole
        // session — and again every time the dock model is rebuilt — for a
        // label only ever shown on one icon at a time. Load it on the first
        // hover and keep it afterwards: destroying it on every hover would
        // churn a window under a fast cursor instead.
        property bool used: false
        // In window-preview mode a running app shows its preview and no name
        // tooltip; only an app with no window to preview gets the name.
        readonly property bool tooltipsEnabled: (Config.options?.dock?.enableAppTooltip ?? false) || GlobalStates.editMode
            || ((Config.options?.dock?.enablePreview ?? true) && !root.appIsRunning)
        readonly property bool hovered: interactionArea.containsMouse
        // Latched on hover, not onLoaded: writing `used` from onLoaded
        // re-evaluated `active` while it was being applied (a binding loop).
        onHoveredChanged: if (hovered && tooltipsEnabled) used = true
        active: tooltipsEnabled && used
        sourceComponent: DockTooltip {
            parentItem: root
            text: root.desktopEntry?.name ?? (root.appToplevel?.appId ?? "")
            showTooltip: tooltipLoader.tooltipsEnabled && tooltipLoader.hovered
        }
    }
}
