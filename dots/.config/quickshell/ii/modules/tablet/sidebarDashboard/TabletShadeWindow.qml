import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions

/**
 * The full-screen surface the tablet notification shade is pulled down onto.
 *
 * The blur behind the shade is done here rather than by Hyprland: a layer rule can only turn
 * blur on or off for the whole surface — its strength is the layer's own fade alpha, which no
 * client can drive per frame. So the shade freezes the screen the instant the pull starts and
 * blurs that snapshot, which is the only way to ramp it smoothly from 0 to full while the
 * finger moves, the way a phone does.
 */
PanelWindow {
    id: root

    readonly property real progress: TabletDashboardGestureController.progress
    readonly property string screenName: root.screen?.name ?? ""
    readonly property bool useBlur: Config.options?.appearance?.transparency?.enable ?? false

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "quickshell:tabletShade"
    WlrLayershell.layer: WlrLayer.Overlay

    // Keyboard focus: only after the shade has completely settled open
    WlrLayershell.keyboardFocus: TabletDashboardGestureController.isSettledOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // When open or dragging the entire window is interactive; when closed only the top edge
    // is, so everything else passes through to the desktop.
    mask: Region {
        item: (root.progress > 0.001 || topMouseDragArea.pressed || TabletDashboardGestureController.tracking) ? contentWrapper : topEdgeCaptureStrip
    }

    // Always mapped so the top edge is ready to be pulled down at any time
    visible: !GlobalStates.screenLocked

    /**
     * The backdrop is rebuilt for every pull, not refreshed.
     *
     * A ScreencopyView keeps the last frame it captured, and asking an existing one for
     * another does not reliably replace it — measured on the drawer, which opened onto the
     * same picture whichever workspace it was opened from, including windows that had been
     * closed for minutes. A view created when the pull starts has nothing to keep, so
     * `hasContent` means "a picture of *this* pull has arrived".
     *
     * Kept as a function because two callers want it: the press on the top edge, which buys
     * the whole press-to-move latency, and the progress hook, which covers hotkey and IPC
     * opens that have no press.
     */
    readonly property string overlayName: "shade"

    property bool wantsBackdrop: false

    function refreshBackdrop() {
        if (root.useBlur)
            root.wantsBackdrop = true;
    }

    onProgressChanged: {
        if (root.progress > 0.001)
            root.refreshBackdrop();
        else if (root.progress <= 0.001)
            root.wantsBackdrop = false;
        GlobalStates.setTabletOverlayOnScreen(root.overlayName, root.progress > 0.001);
    }

    Component.onCompleted: GlobalStates.setTabletOverlayOnScreen(root.overlayName, root.progress > 0.001)

    Connections {
        target: TabletDashboardGestureController
        function onIsSettledOpenChanged() {
            if (TabletDashboardGestureController.isSettledOpen && root.visible) {
                GlobalFocusGrab.addDismissable(root);
            } else {
                GlobalFocusGrab.removeDismissable(root);
            }
        }
    }

    Component.onDestruction: GlobalFocusGrab.removeDismissable(root)

    Connections {
        target: GlobalFocusGrab
        function onDismissed() {
            TabletDashboardGestureController.close();
        }
    }

    Item {
        id: contentWrapper
        anchors.fill: parent
        focus: TabletDashboardGestureController.isSettledOpen

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                TabletDashboardGestureController.close();
            }
        }

        // ── FROZEN BACKDROP ──────────────────────────────────────────────────
        // Covers the whole screen from the first millimetre of the pull, sharp at progress 0
        // and indistinguishable from the live desktop, then blurs with the drag.
        Item {
            id: backdrop
            anchors.fill: parent
            visible: root.useBlur && root.progress > 0.001 && (backdropLoader.item?.hasContent ?? false)
            layer.enabled: backdrop.visible
            layer.effect: MultiEffect {
                // Auto padding grows the effect item past the source and shifts the whole
                // capture down, leaving a sharp strip along the top edge.
                autoPaddingEnabled: false
                blurEnabled: true
                blurMax: 96
                blurMultiplier: 1.4
                blur: Math.min(1.0, root.progress * 1.15)
            }

            Loader {
                id: backdropLoader
                anchors.fill: parent
                active: root.wantsBackdrop
                    && !GlobalStates.otherTabletOverlayOnScreen(root.overlayName)

                sourceComponent: ScreencopyView {
                    anchors.fill: parent
                    captureSource: root.screen
                    // Live re-capture also sees the shade's own blurred output, so it
                    // smears — opt-in only, from Settings › Sidebars.
                    live: Config.options?.sidebar?.tabletShade?.liveBackdrop ?? false
                    Component.onCompleted: captureFrame()
                }
            }
        }

        // ── SCRIM ────────────────────────────────────────────────────────────
        // Dim over the blurred backdrop; without transparency there is no backdrop and this is
        // the opaque surface the shade sits on.
        Rectangle {
            id: scrim
            anchors.fill: parent
            visible: root.progress > 0.001

            // Layer 0: the shade drops the card that used to sit behind the quick toggles, so
            // the tiles (layer 2) and the notification card (layer 1) stack straight onto this.
            // A surfaceContainer background would be the exact colour of an untoggled tile.
            color: root.useBlur ? ColorUtils.transparentize(Appearance.colors.colScrim, 1.0 - root.progress) : Appearance.colors.colLayer0
            opacity: root.useBlur ? 1.0 : root.progress

            // Faint themed wash over the dim, so the blurred desktop still reads as part of the
            // shade's palette the way the opaque mode does.
            Rectangle {
                anchors.fill: parent
                visible: root.useBlur
                color: Appearance.colors.colLayer0
                opacity: 0.22 * root.progress
            }

            ShadeDragArea {
                id: shadeDragArea
                tapCloses: true
            }
        }

        // ── SHADE SHEET ──────────────────────────────────────────────────────
        // Android *reveals* the shade rather than sliding it: the content sits at its final
        // position and the descending edge uncovers it, so every card looks like it is growing
        // downward. Translating the whole sheet instead showed the bottom of the dashboard
        // first and left the content static relative to the finger, which read as no animation
        // at all. A little parallax keeps it feeling attached to the drag.
        Item {
            id: shadeSheet
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
            }
            height: Math.round(root.height * root.progress)
            visible: root.progress > 0.001
            clip: true

            TabletDashboardContent {
                width: shadeSheet.width
                height: root.height
                y: -(1.0 - root.progress) * root.height * 0.08
                onDismissRequested: TabletDashboardGestureController.close()
            }
        }

        Item {
            id: shadeTopHandle
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
            }
            height: Math.max(48, Math.round(root.height * 0.075))
            visible: root.progress > 0.001
            z: 500

            ShadeDragArea {}
        }

        // ── TOP EDGE CAPTURE STRIP (independent from the bar) ────────────────
        // The top edge captures click-and-drag down from mouse, touch or tablet stylus
        Item {
            id: topEdgeCaptureStrip
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
            }
            height: Math.max(2, Config.options?.sidebar?.tabletShade?.edgeDragHeight ?? 8)
            z: 9999

            MouseArea {
                id: topMouseDragArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                preventStealing: true
                // Only owns the edge while the shade is mostly closed; latched on isTracking so
                // an open drag that crosses the halfway point doesn't lose its own grab.
                enabled: TabletDashboardGestureController.progress < 0.5 || topMouseDragArea.isTracking

                property real startY: 0
                property real lastY: 0
                property real lastTime: 0
                property real calculatedVelocity: 0
                property bool isTracking: false

                onPressed: mouse => {
                    if (TabletDashboardGestureController.isSettledOpen) return;
                    root.refreshBackdrop();
                    startY = mouse.y;
                    lastY = mouse.y;
                    lastTime = Date.now();
                    calculatedVelocity = 0;
                    isTracking = true;
                    TabletDashboardGestureController.startTracking(root.screenName);
                }

                onPositionChanged: mouse => {
                    if (!isTracking) return;
                    const now = Date.now();
                    const dt = Math.max(1, now - lastTime);
                    calculatedVelocity = ((mouse.y - lastY) / dt) * 1000.0;
                    lastY = mouse.y;
                    lastTime = now;

                    const deltaY = mouse.y - startY;
                    const p = Math.max(0.0, Math.min(1.0, deltaY / TabletDashboardGestureController.dragDistance(root.height)));
                    TabletDashboardGestureController.updateProgress(p, calculatedVelocity);
                }

                onReleased: mouse => {
                    if (!isTracking) return;
                    isTracking = false;
                    TabletDashboardGestureController.endTracking(calculatedVelocity);
                }

                onCanceled: {
                    if (isTracking) {
                        isTracking = false;
                        TabletDashboardGestureController.cancelTracking();
                    }
                }
            }
        }
    }

    // Drag surfaces for the shade. Both are outside the sliding surface on purpose: an area
    // that moves with the sheet would see its own coordinate shift as pointer movement and
    // feed the gesture back into itself.
    component ShadeDragArea: MouseArea {
        id: dragArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        preventStealing: true

        // A press that never turns into a drag counts as a tap outside the content.
        property bool tapCloses: false

        property real startY: 0
        property real startProgress: 1.0
        property real lastY: 0
        property real lastTime: 0
        property real calculatedVelocity: 0
        property bool dragging: false
        property bool moved: false

        onPressed: mouse => {
            dragArea.startY = mouse.y;
            dragArea.lastY = mouse.y;
            dragArea.lastTime = Date.now();
            dragArea.calculatedVelocity = 0;
            dragArea.dragging = false;
            dragArea.moved = false;
            dragArea.startProgress = TabletDashboardGestureController.progress;
        }

        onPositionChanged: mouse => {
            const deltaY = mouse.y - dragArea.startY;
            if (!dragArea.dragging) {
                if (Math.abs(deltaY) < 10)
                    return;
                dragArea.dragging = true;
                TabletDashboardGestureController.startTracking(root.screenName);
            }
            const now = Date.now();
            const dt = Math.max(1, now - dragArea.lastTime);
            dragArea.calculatedVelocity = ((mouse.y - dragArea.lastY) / dt) * 1000.0;
            dragArea.lastY = mouse.y;
            dragArea.lastTime = now;
            dragArea.moved = true;

            const p = dragArea.startProgress + deltaY / TabletDashboardGestureController.dragDistance(root.height);
            TabletDashboardGestureController.updateProgress(Math.max(0.0, Math.min(1.0, p)), dragArea.calculatedVelocity);
        }

        onReleased: {
            if (dragArea.dragging) {
                dragArea.dragging = false;
                TabletDashboardGestureController.endTracking(dragArea.calculatedVelocity, dragArea.startProgress);
            } else if (dragArea.tapCloses && !dragArea.moved && TabletDashboardGestureController.progress > 0.5) {
                TabletDashboardGestureController.close();
            }
        }

        // Treated as a release: if something steals the grab mid-drag, settling by position
        // is far less jarring than snapping straight back to where the gesture started.
        onCanceled: {
            if (dragArea.dragging) {
                dragArea.dragging = false;
                TabletDashboardGestureController.endTracking(dragArea.calculatedVelocity, dragArea.startProgress);
            }
        }
    }
}
