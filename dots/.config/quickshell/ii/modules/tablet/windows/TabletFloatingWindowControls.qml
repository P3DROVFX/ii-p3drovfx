pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "TabletWindowGeometry.js" as WindowGeometry

/**
 * A title strip and a corner handle for the floating window in front.
 *
 * Hyprland can move and resize a floating window, but only through bindings that follow a
 * pointer: `movewindow` and `resizewindow` are mouse drags, and there is no touch
 * equivalent. So a tablet that floats its windows has no way to arrange them — which is why
 * this exists, and why it is drawn by the shell rather than asked for from the compositor.
 *
 * It is a layer surface, not a decoration: the compositor owns the window and this only
 * knows where it is. That has one consequence worth stating, because it looks like a bug —
 * the strip follows the window one client-list refresh behind, so a fast drag shows it
 * catching up. Dragging *by* the strip does not have that problem, because there the strip's
 * own position is what leads and the window follows.
 */
Scope {
    id: root

    Variants {
        model: Quickshell.screens

        delegate: Scope {
            id: screenScope
            required property ShellScreen modelData

            Loader {
                active: Config.ready && (Config.options?.tablet?.windows?.touchControls ?? true)
                sourceComponent: PanelWindow {
                    id: controlsWindow

                    readonly property string screenName: controlsWindow.screen?.name ?? ""
                    readonly property var settings: Config.options?.tablet?.windows

                    /// The Hyprland monitor this surface is on, for converting the window's
                    /// layout coordinates into this surface's own.
                    readonly property var monitor: {
                        for (const candidate of (HyprlandData.monitors ?? [])) {
                            if (String(candidate?.name ?? "") === controlsWindow.screenName)
                                return candidate;
                        }
                        return null;
                    }

                    /**
                     * The window the controls belong to.
                     *
                     * Only ever the focused one. A strip per floating window would be a set
                     * of controls the user has to aim at; one strip that follows focus is a
                     * title bar, and tapping a window to focus it is already how you choose
                     * which window the controls are for.
                     */
                    readonly property var target: {
                        const client = TabletWindowActions.focusedClient();
                        if (!client || !client.floating || client.fullscreen)
                            return null;
                        const clientMonitor = TabletWindowActions.monitorForClient(client);
                        if (String(clientMonitor?.name ?? "") !== controlsWindow.screenName)
                            return null;
                        return client;
                    }

                    readonly property string targetAddress: TabletWindowActions.normalizeAddress(controlsWindow.target?.address)

                    // Shell surfaces cover the window entirely; controls for something nobody
                    // can see are controls in the way.
                    readonly property bool shellSurfaceOpen: GlobalStates.appDrawerOpen
                        || GlobalStates.recentsOpen
                        || GlobalStates.dashboardPanelOpen
                        || GlobalStates.sessionOpen
                        || GlobalStates.screenLocked

                    readonly property bool shown: controlsWindow.target !== null && !controlsWindow.shellSurfaceOpen

                    // ── Geometry ────────────────────────────────────────────
                    // `at` and `size` are layout coordinates; this surface's origin is the
                    // monitor's. Everything below is in surface coordinates.
                    readonly property real windowX: (Number(controlsWindow.target?.at?.[0] ?? 0))
                        - Number(controlsWindow.monitor?.x ?? 0)
                    readonly property real windowY: (Number(controlsWindow.target?.at?.[1] ?? 0))
                        - Number(controlsWindow.monitor?.y ?? 0)
                    readonly property real windowWidth: Number(controlsWindow.target?.size?.[0] ?? 0)
                    readonly property real windowHeight: Number(controlsWindow.target?.size?.[1] ?? 0)

                    readonly property real stripHeight: Math.max(Appearance.sizes.minimumTouchTarget,
                                                                 controlsWindow.settings?.touchControlsHeight ?? 40)
                    readonly property real handleSize: Math.max(Appearance.sizes.minimumTouchTarget, 44)
                    readonly property real gap: 6

                    /// Above the window when there is room, otherwise tucked against its top
                    /// edge from inside. A strip that runs off the top of the screen is a
                    /// window that can no longer be moved.
                    readonly property bool stripAbove: controlsWindow.windowY - controlsWindow.stripHeight
                        - controlsWindow.gap >= 0

                    anchors {
                        top: true
                        bottom: true
                        left: true
                        right: true
                    }
                    color: "transparent"
                    exclusionMode: ExclusionMode.Ignore
                    WlrLayershell.namespace: "quickshell:tabletWindowControls"
                    WlrLayershell.layer: WlrLayer.Top
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                    visible: !GlobalStates.screenLocked

                    // Only the strip and the corner take input. Everything else on this
                    // full-screen surface has to reach the application underneath.
                    mask: Region {
                        regions: [stripRegion, handleRegion]
                    }

                    Region {
                        id: stripRegion
                        item: strip
                        intersection: controlsWindow.shown ? Intersection.Combine : Intersection.Subtract
                    }

                    Region {
                        id: handleRegion
                        item: resizeHandle
                        intersection: controlsWindow.shown ? Intersection.Combine : Intersection.Subtract
                    }

                    /**
                     * Where a live drag has got to, or -1 for "read the window".
                     *
                     * A drag has to lead the window rather than follow it: dispatching a move
                     * and then waiting for `hyprctl clients` to report the new position back
                     * would put a whole client-list refresh between the finger and the strip.
                     * These hold the finger's answer for as long as the finger is down.
                     */
                    property real dragX: -1
                    property real dragY: -1
                    property real liveWidth: -1
                    property real liveHeight: -1

                    /**
                     * The last geometry dispatched and not yet seen coming back, or -1.
                     *
                     * Lifting the finger used to drop straight back to the reported
                     * position, and Hyprland reports nothing at all for a pixel move — so
                     * the strip snapped back to wherever the window had been *before* the
                     * drag and stayed there. Holding the request until the report agrees
                     * with it is what closes that gap; see TabletWindowGeometry.js.
                     */
                    property real pendingX: -1
                    property real pendingY: -1
                    property real pendingWidth: -1
                    property real pendingHeight: -1

                    readonly property real effectiveX: WindowGeometry.effective(
                        controlsWindow.dragX, controlsWindow.pendingX, controlsWindow.windowX)
                    readonly property real effectiveY: WindowGeometry.effective(
                        controlsWindow.dragY, controlsWindow.pendingY, controlsWindow.windowY)
                    readonly property real effectiveWidth: WindowGeometry.effective(
                        controlsWindow.liveWidth, controlsWindow.pendingWidth, controlsWindow.windowWidth)
                    readonly property real effectiveHeight: WindowGeometry.effective(
                        controlsWindow.liveHeight, controlsWindow.pendingHeight, controlsWindow.windowHeight)

                    /// True while the finger is down. The strip is animated between
                    /// positions except now, when it has to be exactly under the finger.
                    readonly property bool dragging: controlsWindow.dragX >= 0 || controlsWindow.liveWidth >= 0

                    function clearPending() {
                        settleTimeout.stop();
                        controlsWindow.pendingX = -1;
                        controlsWindow.pendingY = -1;
                        controlsWindow.pendingWidth = -1;
                        controlsWindow.pendingHeight = -1;
                    }

                    /// The report caught up: stop overriding it.
                    ///
                    /// Watched rather than polled, because a refresh is a process and the
                    /// only thing that reliably triggers one after a pixel move is the
                    /// request TabletWindowActions makes on our behalf.
                    onWindowXChanged: controlsWindow.settleIfReported()
                    onWindowYChanged: controlsWindow.settleIfReported()
                    onWindowWidthChanged: controlsWindow.settleIfReported()
                    onWindowHeightChanged: controlsWindow.settleIfReported()

                    function settleIfReported() {
                        if (controlsWindow.pendingX < 0 && controlsWindow.pendingY < 0
                                && controlsWindow.pendingWidth < 0 && controlsWindow.pendingHeight < 0)
                            return;
                        const reported = {
                            x: controlsWindow.windowX,
                            y: controlsWindow.windowY,
                            width: controlsWindow.windowWidth,
                            height: controlsWindow.windowHeight
                        };
                        const pending = {
                            x: controlsWindow.pendingX,
                            y: controlsWindow.pendingY,
                            width: controlsWindow.pendingWidth,
                            height: controlsWindow.pendingHeight
                        };
                        if (WindowGeometry.geometrySettled(reported, pending))
                            controlsWindow.clearPending();
                    }

                    // A compositor is allowed to honour a request approximately — clamp it
                    // to the monitor, apply a size floor — and then the report never matches
                    // and the override would be held forever. Short enough that the
                    // correction reads as the window settling rather than as a jump.
                    Timer {
                        id: settleTimeout
                        interval: 600
                        repeat: false
                        onTriggered: controlsWindow.clearPending()
                    }

                    // The window in front changed: whatever was pending belonged to the
                    // last one, and applying it to this one would place the strip nowhere
                    // near it.
                    onTargetAddressChanged: controlsWindow.clearPending()

                    /// One dispatch per frame at most. A move per mouse event is a hundred
                    /// IPC round trips a second, and the compositor coalesces them anyway.
                    Timer {
                        id: commitTimer
                        interval: 16
                        repeat: false
                        property bool geometryPending: false
                        onTriggered: {
                            if (controlsWindow.targetAddress.length === 0)
                                return;
                            const originX = controlsWindow.effectiveX + Number(controlsWindow.monitor?.x ?? 0);
                            const originY = controlsWindow.effectiveY + Number(controlsWindow.monitor?.y ?? 0);
                            if (commitTimer.geometryPending) {
                                TabletWindowActions.setGeometry(controlsWindow.targetAddress, originX, originY,
                                                                controlsWindow.effectiveWidth,
                                                                controlsWindow.effectiveHeight);
                            } else {
                                TabletWindowActions.moveTo(controlsWindow.targetAddress, originX, originY);
                            }
                        }
                    }

                    function commitMove() {
                        commitTimer.geometryPending = false;
                        if (!commitTimer.running)
                            commitTimer.start();
                    }

                    function commitGeometry() {
                        commitTimer.geometryPending = true;
                        if (!commitTimer.running)
                            commitTimer.start();
                    }

                    function endDrag() {
                        commitTimer.stop();
                        // Read before the overrides are cleared: these *are* the finger's
                        // final answer, and they are what has to be held until the report
                        // agrees. Clearing first and reading `effective*` afterwards would
                        // hand back the stale reported position, which is the bug.
                        const finalX = controlsWindow.effectiveX;
                        const finalY = controlsWindow.effectiveY;
                        const resized = controlsWindow.liveWidth >= 0 || controlsWindow.liveHeight >= 0;
                        const finalWidth = controlsWindow.effectiveWidth;
                        const finalHeight = controlsWindow.effectiveHeight;

                        controlsWindow.dragX = -1;
                        controlsWindow.dragY = -1;
                        controlsWindow.liveWidth = -1;
                        controlsWindow.liveHeight = -1;

                        if (controlsWindow.targetAddress.length === 0) {
                            controlsWindow.clearPending();
                            return;
                        }

                        const originX = finalX + Number(controlsWindow.monitor?.x ?? 0);
                        const originY = finalY + Number(controlsWindow.monitor?.y ?? 0);
                        if (resized) {
                            TabletWindowActions.setGeometry(controlsWindow.targetAddress, originX, originY,
                                                            finalWidth, finalHeight);
                        } else {
                            TabletWindowActions.moveTo(controlsWindow.targetAddress, originX, originY);
                        }

                        controlsWindow.pendingX = finalX;
                        controlsWindow.pendingY = finalY;
                        controlsWindow.pendingWidth = resized ? finalWidth : -1;
                        controlsWindow.pendingHeight = resized ? finalHeight : -1;
                        settleTimeout.restart();
                        // Already asked for by the dispatch above; asking again here is what
                        // guarantees one refresh lands after the *last* commit rather than
                        // the debounce swallowing it into the middle of the drag.
                        TabletWindowActions.requestGeometryRefresh();
                    }

                    // ── The strip ───────────────────────────────────────────
                    Rectangle {
                        id: strip
                        x: controlsWindow.effectiveX
                        y: controlsWindow.stripAbove
                            ? controlsWindow.effectiveY - controlsWindow.stripHeight - controlsWindow.gap
                            : controlsWindow.effectiveY + controlsWindow.gap
                        width: Math.max(controlsWindow.stripHeight * 3, controlsWindow.effectiveWidth)
                        height: controlsWindow.stripHeight
                        radius: Appearance.rounding.full

                        // Hyprland animates a window into its new place; `hyprctl clients`
                        // reports the destination the moment it is decided. Without this the
                        // strip arrives first and waits there while the window slides in
                        // under it, which is most of what "the handles don't follow the
                        // window" looks like. Off during a drag, where the strip has to be
                        // exactly under the finger and nowhere else.
                        Behavior on x {
                            enabled: !controlsWindow.dragging
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(strip)
                        }
                        Behavior on y {
                            enabled: !controlsWindow.dragging
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(strip)
                        }
                        Behavior on width {
                            enabled: !controlsWindow.dragging
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(strip)
                        }
                        color: Appearance.colors.colLayer1
                        visible: controlsWindow.shown
                        opacity: controlsWindow.shown ? 1 : 0

                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(strip)
                        }

                        // The whole strip is the handle, minus the buttons at its right end:
                        // a finger aiming at a title bar aims at the middle of it.
                        MouseArea {
                            id: stripDrag
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.right: stripButtons.left

                            property real pressGlobalX: 0
                            property real pressGlobalY: 0
                            property real originX: 0
                            property real originY: 0

                            onPressed: mouse => {
                                const point = stripDrag.mapToItem(null, mouse.x, mouse.y);
                                stripDrag.pressGlobalX = point.x;
                                stripDrag.pressGlobalY = point.y;
                                // Where the strip is drawn, not what the compositor last
                                // reported: a drag started while the previous one is still
                                // unconfirmed would otherwise take its origin from the old
                                // position and throw the window back there on the first
                                // millimetre of movement.
                                stripDrag.originX = controlsWindow.effectiveX;
                                stripDrag.originY = controlsWindow.effectiveY;
                                controlsWindow.clearPending();
                                controlsWindow.dragX = stripDrag.originX;
                                controlsWindow.dragY = stripDrag.originY;
                            }

                            onPositionChanged: mouse => {
                                if (!stripDrag.pressed)
                                    return;
                                const point = stripDrag.mapToItem(null, mouse.x, mouse.y);
                                controlsWindow.dragX = stripDrag.originX + (point.x - stripDrag.pressGlobalX);
                                controlsWindow.dragY = stripDrag.originY + (point.y - stripDrag.pressGlobalY);
                                controlsWindow.commitMove();
                            }

                            onReleased: controlsWindow.endDrag()
                            onCanceled: controlsWindow.endDrag()
                        }

                        MaterialSymbol {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: "drag_indicator"
                            iconSize: Math.round(controlsWindow.stripHeight * 0.5)
                            color: Appearance.colors.colOnLayer1
                            opacity: 0.7
                        }

                        StyledText {
                            anchors.left: parent.left
                            anchors.leftMargin: 12 + Math.round(controlsWindow.stripHeight * 0.5) + 8
                            anchors.right: stripButtons.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: String(controlsWindow.target?.title ?? controlsWindow.target?.class ?? "")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                        }

                        RowLayout {
                            id: stripButtons
                            anchors.right: parent.right
                            anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            TabletWindowControlButton {
                                symbol: "filter_center_focus"
                                controlSize: controlsWindow.stripHeight - 8
                                releaseAction: () => TabletWindowActions.centerWindow(controlsWindow.targetAddress)
                            }

                            TabletWindowControlButton {
                                // Back into the layout: the point of floating everything is
                                // that it is a default, not a cage.
                                symbol: "grid_view"
                                controlSize: controlsWindow.stripHeight - 8
                                releaseAction: () => TabletWindowActions.setFloating(controlsWindow.targetAddress, false)
                            }

                            TabletWindowControlButton {
                                symbol: "fullscreen"
                                controlSize: controlsWindow.stripHeight - 8
                                releaseAction: () => TabletWindowActions.toggleFullscreen(controlsWindow.targetAddress)
                            }

                            TabletWindowControlButton {
                                symbol: "close"
                                controlSize: controlsWindow.stripHeight - 8
                                releaseAction: () => TabletWindowActions.closeWindow(controlsWindow.targetAddress)
                            }
                        }
                    }

                    // ── The corner handle ───────────────────────────────────
                    Rectangle {
                        id: resizeHandle
                        x: controlsWindow.effectiveX + controlsWindow.effectiveWidth - controlsWindow.handleSize * 0.6
                        y: controlsWindow.effectiveY + controlsWindow.effectiveHeight - controlsWindow.handleSize * 0.6
                        width: controlsWindow.handleSize
                        height: controlsWindow.handleSize
                        radius: Appearance.rounding.full
                        color: resizeDrag.pressed ? Appearance.colors.colPrimary : Appearance.colors.colLayer1

                        // Same reason as the strip: travel with the window rather than
                        // arriving at its destination ahead of it.
                        Behavior on x {
                            enabled: !controlsWindow.dragging
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(resizeHandle)
                        }
                        Behavior on y {
                            enabled: !controlsWindow.dragging
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(resizeHandle)
                        }
                        visible: controlsWindow.shown
                        opacity: controlsWindow.shown ? 1 : 0

                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(resizeHandle)
                        }
                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(resizeHandle)
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "south_east"
                            iconSize: Math.round(controlsWindow.handleSize * 0.45)
                            color: resizeDrag.pressed
                                ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
                        }

                        MouseArea {
                            id: resizeDrag
                            anchors.fill: parent

                            property real pressGlobalX: 0
                            property real pressGlobalY: 0
                            property real originWidth: 0
                            property real originHeight: 0

                            onPressed: mouse => {
                                const point = resizeDrag.mapToItem(null, mouse.x, mouse.y);
                                resizeDrag.pressGlobalX = point.x;
                                resizeDrag.pressGlobalY = point.y;
                                resizeDrag.originWidth = controlsWindow.effectiveWidth;
                                resizeDrag.originHeight = controlsWindow.effectiveHeight;
                                // The top-left is held for the whole gesture: `resize`
                                // recentres, so without pinning the origin the window walks
                                // up and left as it grows.
                                const heldX = controlsWindow.effectiveX;
                                const heldY = controlsWindow.effectiveY;
                                controlsWindow.clearPending();
                                controlsWindow.dragX = heldX;
                                controlsWindow.dragY = heldY;
                                controlsWindow.liveWidth = resizeDrag.originWidth;
                                controlsWindow.liveHeight = resizeDrag.originHeight;
                            }

                            onPositionChanged: mouse => {
                                if (!resizeDrag.pressed)
                                    return;
                                const point = resizeDrag.mapToItem(null, mouse.x, mouse.y);
                                controlsWindow.liveWidth = Math.max(TabletWindowActions.minimumWidth,
                                    resizeDrag.originWidth + (point.x - resizeDrag.pressGlobalX));
                                controlsWindow.liveHeight = Math.max(TabletWindowActions.minimumHeight,
                                    resizeDrag.originHeight + (point.y - resizeDrag.pressGlobalY));
                                controlsWindow.commitGeometry();
                            }

                            onReleased: controlsWindow.endDrag()
                            onCanceled: controlsWindow.endDrag()
                        }
                    }
                }
            }
        }
    }
}
