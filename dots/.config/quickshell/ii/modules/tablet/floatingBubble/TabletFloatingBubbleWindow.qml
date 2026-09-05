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
 * The bubble's surface: the circle, and the sheet of actions it opens.
 *
 * Three decisions worth stating, because each of them is the reason something works:
 *
 *  - **Overlay layer**, so it survives a fullscreen window. That is the whole point — the
 *    moment an application takes the screen is the moment every other way into the shell
 *    becomes hard to reach. `showOverFullscreen` drops it to Top for anyone who would
 *    rather a video player won.
 *  - **An input mask around the circle and the sheet only.** This surface is the size of
 *    the screen; without a mask it would swallow every touch on the desktop. The mask is
 *    what makes an always-present overlay cost nothing when nobody is using it.
 *  - **Its own scrim rather than a focus grab.** A HyprlandFocusGrab would work, but the
 *    shared one dismisses every registered surface at once, so tapping away from the sheet
 *    would also close the shade or the drawer if either happened to be open. A scrim inside
 *    this surface closes exactly this sheet, and only while the sheet is up.
 *
 * The sheet opens towards the side with more room. A panel that always opened rightwards
 * would be off-screen exactly when the bubble is parked on the right edge, which — since it
 * snaps to an edge — is most of the time.
 */
PanelWindow {
    id: root

    readonly property string screenName: root.screen?.name ?? ""
    readonly property var settings: Config.options?.tablet?.bubble

    readonly property real bubbleSize: Math.max(40, Math.min(96, root.settings?.size ?? 56))
    readonly property real edgeMargin: 12
    readonly property bool snapToEdge: root.settings?.snapToEdge ?? true

    property bool sheetOpen: false

    /**
     * Where the bubble is, as a fraction of the travel it has.
     *
     * A fraction rather than a pixel position, and derived rather than assigned, because the
     * surface reports its size more than once while it is coming up. A stored pixel position
     * seeded from one of those early sizes puts the bubble in a corner of a screen that does
     * not exist — which is exactly what happened: the first attempt latched onto a 100x48
     * surface and parked the bubble at the top left of it. With a fraction there is nothing
     * to latch onto; every size change simply re-derives the same relative place.
     */
    property real fractionX: -1
    property real fractionY: -1

    readonly property real travelX: Math.max(0, root.width - root.bubbleSize - root.edgeMargin * 2)
    readonly property real travelY: Math.max(0, root.height - root.bubbleSize - root.edgeMargin * 2)

    /// Bottom right, away from the bar and clear of the dock's own controls.
    readonly property real defaultFractionX: 1
    readonly property real defaultFractionY: 0.62

    readonly property real effectiveFractionX: root.fractionX < 0 ? root.defaultFractionX : root.fractionX
    readonly property real effectiveFractionY: root.fractionY < 0 ? root.defaultFractionY : root.fractionY

    readonly property real bubbleX: root.edgeMargin + root.effectiveFractionX * root.travelX
    readonly property real bubbleY: root.edgeMargin + root.effectiveFractionY * root.travelY

    function clamp01(value) {
        return Math.max(0, Math.min(1, value));
    }

    function restorePosition() {
        const storedX = Number(Persistent.states?.tablet?.bubbleX ?? -1);
        const storedY = Number(Persistent.states?.tablet?.bubbleY ?? -1);
        root.fractionX = storedX < 0 ? -1 : root.clamp01(storedX);
        root.fractionY = storedY < 0 ? -1 : root.clamp01(storedY);
    }

    function savePosition() {
        if (!Persistent.states?.tablet)
            return;
        Persistent.states.tablet.bubbleX = root.effectiveFractionX;
        Persistent.states.tablet.bubbleY = root.effectiveFractionY;
        Persistent.states.tablet.bubbleOnRight = root.opensLeft;
    }

    Component.onCompleted: root.restorePosition()

    /// The sheet goes towards the middle of the screen, which is where the room is.
    readonly property bool opensLeft: root.effectiveFractionX > 0.5

    // ── Idle fade ───────────────────────────────────────────────────────────
    // A control that is always on top has to be able to stop competing with what it is on
    // top of. It never disappears — an invisible control is a lost one — it only dims.
    readonly property int idleAfterMs: Math.max(0, (root.settings?.idleAfterSeconds ?? 4)) * 1000
    readonly property real idleOpacity: Math.max(0.15, Math.min(1, (root.settings?.idleOpacity ?? 65) / 100))
    property bool idle: false

    function wake() {
        root.idle = false;
        if (root.idleAfterMs > 0)
            idleTimer.restart();
    }

    Timer {
        id: idleTimer
        interval: Math.max(1, root.idleAfterMs)
        repeat: false
        onTriggered: {
            if (!root.sheetOpen && !bubbleArea.pressed)
                root.idle = true;
        }
    }

    onSheetOpenChanged: root.wake()

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:tabletBubble"
    WlrLayershell.layer: (root.settings?.showOverFullscreen ?? true) ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Hidden on the lock screen, where "float the current window" is both meaningless and a
    // way past the lock.
    visible: !GlobalStates.screenLocked

    mask: Region {
        regions: [scrimRegion, bubbleRegion, sheetRegion]
    }

    Region {
        id: scrimRegion
        item: scrim
        intersection: root.sheetOpen ? Intersection.Combine : Intersection.Subtract
    }

    Region {
        id: bubbleRegion
        item: bubble
    }

    Region {
        id: sheetRegion
        item: sheet
        intersection: root.sheetOpen ? Intersection.Combine : Intersection.Subtract
    }

    // ── Actions ─────────────────────────────────────────────────────────────
    /**
     * What the sheet offers, resolved against the shared registry.
     *
     * The ids are the same ones the gesture bindings use, so the bubble is a new way to
     * reach the shell's actions rather than a second catalogue to keep in step with the
     * first. Anything the running family cannot perform is dropped rather than drawn as a
     * tile that does nothing — the same rule the gesture bindings follow.
     */
    readonly property var sheetActions: {
        const resolved = [];
        for (const actionId of (root.settings?.actions ?? [])) {
            const id = String(actionId ?? "");
            if (id.length === 0 || id === "none")
                continue;
            const action = ShellActionRegistry.actionById(id);
            if (!action || action.id === "none" || action.id !== id)
                continue;
            if (!TouchGestureActionRegistry.availableForFamily(action, PanelFamily.current))
                continue;
            resolved.push(action);
        }
        return resolved;
    }

    readonly property var prominentActions: root.sheetActions.filter(action => action.prominent)
    readonly property var gridActions: root.sheetActions.filter(action => !action.prominent)

    function runAction(actionId) {
        root.sheetOpen = false;
        // After the sheet is down: several of these focus or move a window, and doing that
        // while a masked overlay is still up hands the focus straight back.
        actionDelay.pendingAction = actionId;
        actionDelay.restart();
    }

    Timer {
        id: actionDelay
        property string pendingAction: ""
        interval: 60
        repeat: false
        onTriggered: {
            const actionId = actionDelay.pendingAction;
            actionDelay.pendingAction = "";
            if (actionId.length > 0)
                ShellActionRegistry.trigger(actionId, root.screenName);
        }
    }

    // ── Scrim ───────────────────────────────────────────────────────────────
    // Declared first, so both the sheet and the bubble sit on top of it.
    Item {
        id: scrim
        anchors.fill: parent

        MouseArea {
            anchors.fill: parent
            enabled: root.sheetOpen
            onPressed: root.sheetOpen = false
        }
    }

    StyledRectangularShadow {
        target: sheet
    }

    // ── The sheet ───────────────────────────────────────────────────────────
    Rectangle {
        id: sheet

        readonly property real tileSize: Math.max(Appearance.sizes.minimumTouchTarget * 1.6, 84)
        readonly property int columns: Math.min(2, Math.max(1, root.gridActions.length))
        readonly property real padding: 14

        width: sheet.columns * sheet.tileSize + (sheet.columns - 1) * 10 + sheet.padding * 2
        height: sheetColumn.implicitHeight + sheet.padding * 2

        // Beside the bubble, on whichever side has the room, vertically centred on it but
        // never off the top or bottom of the screen.
        x: root.opensLeft
            ? Math.max(root.edgeMargin, root.bubbleX - sheet.width - 10)
            : Math.min(root.width - sheet.width - root.edgeMargin, root.bubbleX + root.bubbleSize + 10)
        y: Math.max(root.edgeMargin,
                    Math.min(root.height - sheet.height - root.edgeMargin,
                             root.bubbleY + root.bubbleSize / 2 - sheet.height / 2))

        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer0
        visible: opacity > 0.01
        opacity: root.sheetOpen ? 1 : 0
        scale: root.sheetOpen ? 1 : 0.92
        transformOrigin: root.opensLeft ? Item.Right : Item.Left

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(sheet)
        }
        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(sheet)
        }

        ColumnLayout {
            id: sheetColumn
            anchors.centerIn: parent
            spacing: 10

            /**
             * The actions that ask for the top of the sheet.
             *
             * A prominent action gets a full-width bar rather than a square in the grid.
             * Live draw is the reason the flag exists: a pen comes out mid-thought, and
             * the control for it has to be the one you cannot miss — not the fourth icon
             * in a grid of eight identical tiles.
             */
            Repeater {
                model: root.prominentActions

                delegate: TabletBubbleActionTile {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.round(sheet.tileSize * 0.68)
                    tileSize: sheet.tileSize
                    wide: true
                    emphasised: true
                    symbol: modelData.icon ?? "bolt"
                    label: Translation.tr(modelData.name ?? "")
                    onTriggered: root.runAction(modelData.id)
                }
            }

            GridLayout {
                id: sheetGrid
                Layout.alignment: Qt.AlignHCenter
                columns: sheet.columns
                columnSpacing: 10
                rowSpacing: 10

                Repeater {
                    model: root.gridActions

                    delegate: TabletBubbleActionTile {
                        required property var modelData
                        tileSize: sheet.tileSize
                        symbol: modelData.icon ?? "bolt"
                        label: Translation.tr(modelData.name ?? "")
                        onTriggered: root.runAction(modelData.id)
                    }
                }
            }
        }

        // An empty action list is a state Settings can produce, so it says so rather than
        // opening as a blank card the user has to guess about.
        StyledText {
            anchors.centerIn: parent
            visible: root.sheetActions.length === 0
            text: Translation.tr("No actions configured")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }

    StyledRectangularShadow {
        target: bubble
    }

    // ── The bubble ──────────────────────────────────────────────────────────
    Rectangle {
        id: bubble
        x: root.bubbleX
        y: root.bubbleY
        width: root.bubbleSize
        height: root.bubbleSize
        radius: Appearance.rounding.full
        color: root.sheetOpen || bubbleArea.pressed
            ? Appearance.colors.colPrimary : Appearance.colors.colLayer1
        opacity: root.idle && !root.sheetOpen ? root.idleOpacity : 1

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(bubble)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(bubble)
        }
        // Only while it is settling back to an edge. During a drag the position IS the
        // finger, and easing that adds lag to a direct manipulation.
        Behavior on x {
            enabled: !bubbleArea.dragging
            animation: Appearance.animation.elementMove.numberAnimation.createObject(bubble)
        }
        Behavior on y {
            enabled: !bubbleArea.dragging
            animation: Appearance.animation.elementMove.numberAnimation.createObject(bubble)
        }

        // A ring, as the request had it and as every control of this kind uses: it says
        // "a control" without claiming to be any one action, which is what a button whose
        // contents the user chooses has to do.
        MaterialSymbol {
            anchors.centerIn: parent
            text: root.sheetOpen ? "close" : "radio_button_unchecked"
            iconSize: Math.round(root.bubbleSize * 0.52)
            color: root.sheetOpen || bubbleArea.pressed
                ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        MouseArea {
            id: bubbleArea
            anchors.fill: parent

            property bool dragging: false
            property real pressSceneX: 0
            property real pressSceneY: 0
            property real originX: 0
            property real originY: 0

            /// Past this the gesture is a drag, and the release must not also count as a tap.
            readonly property real dragThreshold: 8

            onPressed: mouse => {
                const point = bubbleArea.mapToItem(null, mouse.x, mouse.y);
                bubbleArea.pressSceneX = point.x;
                bubbleArea.pressSceneY = point.y;
                bubbleArea.originX = root.bubbleX;
                bubbleArea.originY = root.bubbleY;
                bubbleArea.dragging = false;
                root.wake();
            }

            onPositionChanged: mouse => {
                if (!bubbleArea.pressed)
                    return;
                const point = bubbleArea.mapToItem(null, mouse.x, mouse.y);
                const dx = point.x - bubbleArea.pressSceneX;
                const dy = point.y - bubbleArea.pressSceneY;
                if (!bubbleArea.dragging && Math.abs(dx) + Math.abs(dy) < bubbleArea.dragThreshold)
                    return;
                if (!bubbleArea.dragging) {
                    bubbleArea.dragging = true;
                    // A sheet anchored to something being dragged is a sheet flying across
                    // the screen. Moving the bubble closes it.
                    root.sheetOpen = false;
                }
                if (root.travelX > 0)
                    root.fractionX = root.clamp01((bubbleArea.originX + dx - root.edgeMargin) / root.travelX);
                if (root.travelY > 0)
                    root.fractionY = root.clamp01((bubbleArea.originY + dy - root.edgeMargin) / root.travelY);
            }

            onReleased: {
                if (!bubbleArea.dragging) {
                    root.sheetOpen = !root.sheetOpen;
                    root.wake();
                    return;
                }
                bubbleArea.dragging = false;
                if (root.snapToEdge) {
                    // To the nearer side, never to a corner: the vertical position is what
                    // the user chose, the horizontal is where a bubble of this kind lives.
                    root.fractionX = root.effectiveFractionX > 0.5 ? 1 : 0;
                }
                root.savePosition();
                root.wake();
            }

            onCanceled: {
                bubbleArea.dragging = false;
                root.wake();
            }
        }
    }
}
