import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * The control center: the dashboard as a floating card instead of a sidebar.
 *
 * Only in the Default shell mode (GlobalStates.controlCenterActive). It answers the same
 * open flag as the sidebar (GlobalStates.dashboardPanelOpen), so every keybind, IPC call and
 * bar button opens it unchanged. The card holds the dashboard's own content in its
 * `controlCenter` form: the four header buttons and the quick toggles, with the same edit
 * mode and dialogs — no banner, notifications or bottom group.
 *
 * It drops from the bar's edge next to the bar's dashboard button (published by
 * BarComponent): down from a top bar, up from a bottom bar, sideways from a vertical one.
 *
 * The window respects every exclusive zone (bar, pinned dock, wrapped frame), so the
 * compositor keeps it clear of them, and its edge on the bar's side is the bar's edge: the
 * card slides out from under the bar, clipped there. It covers the rest of the free area so
 * a click off the card closes it, and stays mapped while the style is on (mapping a large
 * layer costs a visible stall per open) with an empty input mask when closed.
 */
Scope {
    id: root

    readonly property bool open: GlobalStates.dashboardPanelOpen
    readonly property bool keepContentLoaded: Config.ready && Config.options.sidebar.keepRightSidebarLoaded

    // 0 = hidden behind the bar's edge, 1 = seated. The spatial curve overshoots a little
    // past 1 on the way in: the light bounce of the drop.
    property real progress: 0
    // Opacity on its own quad clock: the card is solid well before the drop settles.
    property real fade: 0
    readonly property bool shown: root.open || root.progress > 0 || root.fade > 0
    readonly property bool contentWanted: root.shown || root.keepContentLoaded

    readonly property string monitorName: GlobalStates.activeRightSidebarMonitor || (Hyprland.focusedMonitor?.name ?? "")
    readonly property var targetScreen: {
        const screens = Array.from(Quickshell.screens);
        return screens.find(s => s.name === root.monitorName) ?? (Quickshell.primaryScreen ?? screens[0] ?? null);
    }

    // The bar's edge: where the card comes from.
    readonly property string edge: BarPlacement.vertical
        ? (BarPlacement.bottom ? "right" : "left")
        : (BarPlacement.bottom ? "bottom" : "top")
    readonly property bool horizontalBar: root.edge === "top" || root.edge === "bottom"

    readonly property real gap: Appearance.sizes.hyprlandGapsOut
    // Extra travel so the shadow is hidden too when the card is tucked behind the bar.
    readonly property real shadowRoom: Appearance.sizes.elevationMargin * 2
    readonly property real cardWidth: Appearance.sizes.sidebarWidth - Appearance.sizes.hyprlandGapsOut * 2

    // Space the compositor keeps for exclusive zones on this monitor: [left, top, right, bottom].
    readonly property var reserved: {
        const monitor = Array.from(HyprlandData.monitors ?? []).find(m => m?.name === root.monitorName);
        const r = monitor?.reserved;
        return (r && r.length === 4) ? r : [0, 0, 0, 0];
    }

    // The dashboard button's centre in screen coordinates, read when the card opens (an
    // item's position is not something a binding can follow). null: no button on this screen.
    property var anchorPoint: null

    function refreshAnchor() {
        const item = GlobalStates.dashboardAnchorItems[root.monitorName];
        const win = item?.hostWindow ?? null;
        const screen = root.targetScreen;
        if (!item || !win || !screen || !item.visible || item.width <= 0) {
            root.anchorPoint = null;
            return;
        }
        const p = item.mapToItem(null, item.width / 2, item.height / 2);
        // Bar windows sit at the screen's origin unless they hug the right or bottom edge.
        let x = p.x;
        let y = p.y;
        if (BarPlacement.vertical && BarPlacement.bottom)
            x += screen.width - win.width;
        if (!BarPlacement.vertical && BarPlacement.bottom)
            y += screen.height - win.height;
        root.anchorPoint = Qt.point(x, y);
    }

    function handleOpenChange() {
        if (root.open) {
            HyprlandData.updateMonitors();
            root.refreshAnchor();
        }
        root.animate();
    }

    // Started from the flag itself: a handler on a Scope's own derived property never ran.
    Component.onCompleted: if (root.open) root.handleOpenChange()

    Connections {
        target: GlobalStates
        function onDashboardPanelOpenChanged() {
            root.handleOpenChange();
        }
        function onDashboardAnchorRevisionChanged() {
            if (root && root.shown)
                root.refreshAnchor();
        }
    }

    // The animations live in the window: a free-standing animation on this Scope has no
    // window to drive it and never advanced.
    signal animateRequested()

    function animate() {
        if (Appearance.reducedMotion) {
            root.progress = root.open ? 1 : 0;
            root.fade = root.open ? 1 : 0;
            return;
        }
        root.animateRequested();
    }

    Loader {
        active: GlobalStates.controlCenterActive && root.targetScreen !== null
        sourceComponent: PanelWindow {
            id: panelWindow

            screen: root.targetScreen
            color: "transparent"
            // Zone 0: placed inside the space every exclusive zone leaves free.
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:controlCenter"

            // See SidebarDashboard: take the keyboard exclusively as the card opens, then
            // step down to on-demand so the pointer goes back to what is under it.
            property bool keyboardExclusive: true
            WlrLayershell.keyboardFocus: !root.open ? WlrKeyboardFocus.None
                : (panelWindow.keyboardExclusive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand)

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // The whole free area (what every exclusive zone leaves), so a click anywhere
            // off the card lands here and closes it. Mapped once and kept: closed, its input
            // mask is empty and it draws nothing.
            readonly property real cardX: {
                if (root.edge === "left")
                    return root.gap;
                if (root.edge === "right")
                    return panelWindow.width - root.gap - root.cardWidth;
                const minX = root.gap;
                const maxX = panelWindow.width - root.gap - root.cardWidth;
                const wanted = root.anchorPoint ? root.anchorPoint.x - root.reserved[0] - root.cardWidth / 2 : maxX;
                return Math.max(minX, Math.min(maxX, wanted));
            }

            mask: Region {
                item: root.open ? outsideCatcher : null
            }

            onVisibleChanged: keyboardFocusDowngrade.stop()

            ParallelAnimation {
                id: enterAnimation
                NumberAnimation {
                    target: root
                    property: "progress"
                    to: 1
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
                }
                NumberAnimation {
                    target: root
                    property: "fade"
                    to: 1
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.OutQuad
                }
            }

            ParallelAnimation {
                id: exitAnimation
                NumberAnimation {
                    target: root
                    property: "progress"
                    to: 0
                    duration: Appearance.animation.elementMoveExit.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
                }
                NumberAnimation {
                    target: root
                    property: "fade"
                    to: 0
                    duration: Appearance.animation.elementMoveExit.duration
                    easing.type: Easing.InQuad
                }
            }

            Connections {
                target: root
                function onAnimateRequested() {
                    enterAnimation.stop();
                    exitAnimation.stop();
                    if (root.open)
                        enterAnimation.start();
                    else
                        exitAnimation.start();
                }
            }

            Timer {
                id: keyboardFocusDowngrade
                interval: 200
                onTriggered: panelWindow.keyboardExclusive = false
            }

            // Not GlobalFocusGrab: on this resident surface Hyprland cleared the grab on
            // the first click, inside the card too, so every button closed the card instead.
            Connections {
                target: root
                function onOpenChanged() {
                    if (root.open) {
                        panelWindow.keyboardExclusive = true;
                        keyboardFocusDowngrade.restart();
                    } else {
                        keyboardFocusDowngrade.stop();
                    }
                }
            }

            Component.onCompleted: if (root.open) keyboardFocusDowngrade.restart()

            MouseArea {
                id: outsideCatcher
                anchors.fill: parent
                enabled: root.open
                acceptedButtons: Qt.AllButtons
                onPressed: GlobalStates.dashboardPanelOpen = false
            }

            ShellRegionTarget {
                target: contentLoader.item
                label: Translation.tr("Control center")
            }

            // The card's resting place inside the window.
            readonly property real maxCardHeight: Math.max(0, panelWindow.height - root.gap * 2)
            readonly property real restX: panelWindow.cardX
            readonly property real restY: {
                if (root.edge === "top")
                    return root.gap;
                if (root.edge === "bottom")
                    return panelWindow.height - root.gap - card.height;
                // Beside a vertical bar: level with the button, kept on screen.
                const reservedTop = root.reserved[1];
                const wanted = root.anchorPoint ? root.anchorPoint.y - reservedTop - card.height / 2 : root.gap;
                return Math.max(root.gap, Math.min(panelWindow.height - root.gap - card.height, wanted));
            }
            // How far the card travels to hide behind the bar's edge.
            readonly property real travel: {
                switch (root.edge) {
                case "top": return -(panelWindow.restY + card.height + root.shadowRoom);
                case "bottom": return panelWindow.height - panelWindow.restY + root.shadowRoom;
                case "left": return -(panelWindow.restX + root.cardWidth + root.shadowRoom);
                default: return panelWindow.width - panelWindow.restX + root.shadowRoom;
                }
            }

            Item {
                id: card
                x: panelWindow.restX
                y: panelWindow.restY
                width: root.cardWidth
                height: contentLoader.item ? contentLoader.item.implicitHeight : 0
                visible: root.shown
                opacity: root.fade
                transform: Translate {
                    x: root.horizontalBar ? 0 : (1 - root.progress) * panelWindow.travel
                    y: root.horizontalBar ? (1 - root.progress) * panelWindow.travel : 0
                }

                // Clicks on the card's own empty space stay on the card.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                }

                RetainedLoader {
                    id: contentLoader
                    anchors.fill: parent
                    requested: root.contentWanted
                    retainFor: 60000
                    // The drop must find the content already built.
                    asynchronous: false
                    focus: root.open
                    sourceComponent: SidebarDashboardContent {
                        controlCenter: true
                        controlCenterMaxHeight: panelWindow.maxCardHeight
                        keepWarm: root.keepContentLoaded
                    }

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            GlobalStates.dashboardPanelOpen = false;
                            event.accepted = true;
                        }
                    }
                }
            }
        }
    }
}
