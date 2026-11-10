import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.overview
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets

/**
 * Real Gnome window picker: the input half.
 *
 * The window captures live on the transition layer below the overview, which
 * takes no input. That layer publishes each window's slot at full open
 * (`GlobalStates.realGnomePickerSlots`, screen coordinates); this item lays a
 * hit area over every slot and draws GNOME Shell's affordances on top of the
 * capture: the app icon on the bottom edge, the title under it on hover and
 * the close button in the corner. Hover is published back so the capture
 * lifts with the pointer.
 */
Item {
    id: root

    required property string screenName
    /** Screen coordinates -> this item's coordinates. */
    property real offsetX: 0
    property real offsetY: 0
    property bool shown: false

    readonly property var slots: GlobalStates.realGnomePickerSlots[root.screenName] ?? []
    readonly property var controller: GlobalStates.overviewBackgroundControllerFor(root.screenName)

    // ── Drag to another workspace or monitor ────────────────────────────────
    // A held window follows the pointer. Resting it at the side edge of a monitor's
    // plane previews the neighbouring workspace by sliding that monitor's strip (a
    // real switch would end the drag - Hyprland releases a held pointer on a focus
    // change). Dropping on a plane moves the window to that monitor's workspace (the
    // previewed one, which it then switches to); dropping straight onto a neighbour
    // beside the plane only moves it; anywhere else it springs back to its slot.
    // The picker that took the press owns the gesture; every monitor's picker draws
    // the held window from the one global rect.
    property string dragAddress: ""
    property point pointer: Qt.point(0, 0)        // global (layout) coordinates
    property point grabFrac: Qt.point(0.5, 0.5)   // where in the slot it was taken
    property rect slotRectG: Qt.rect(0, 0, 0, 0)  // the slot at press, global
    property size shrunk: Qt.size(0, 0)
    property real shrinkT: 0
    property real returnT: 0
    property real dropT: 0
    property rect releaseRect: Qt.rect(0, 0, 0, 0)
    property string phase: ""
    readonly property bool ownsDrag: root.dragAddress !== ""
    readonly property bool dragging: GlobalStates.realGnomeDragPhase === "drag"

    readonly property var screenObj: Quickshell.screens.find(s => s.name === root.screenName) ?? null
    readonly property real screenX: root.screenObj ? root.screenObj.x : 0
    readonly property real screenY: root.screenObj ? root.screenObj.y : 0

    function screenAt(gx, gy) {
        return Quickshell.screens.find(s => gx >= s.x && gx < s.x + s.width && gy >= s.y && gy < s.y + s.height) ?? null;
    }
    function planeOf(screen) {
        if (!screen)
            return Qt.rect(0, 0, 0, 0);
        const controller = GlobalStates.overviewBackgroundControllerFor(screen.name);
        const t = controller ? controller.realGnomeTarget : Qt.rect(0, 0, 0, 0);
        return Qt.rect(screen.x + t.x, screen.y + t.y, t.width, t.height);
    }
    function activeWsOf(screenName) {
        const monitor = Hyprland.monitors.values.find(m => m.name === screenName);
        return Math.max(1, monitor?.activeWorkspace?.id ?? 1);
    }

    readonly property var pointerScreen: root.ownsDrag ? root.screenAt(root.pointer.x, root.pointer.y) : null
    readonly property string pointerScreenName: root.pointerScreen ? root.pointerScreen.name : ""
    readonly property rect pointerPlane: root.planeOf(root.pointerScreen)
    readonly property int edgeSide: root.phase !== "drag" || root.pointerPlane.width <= 0 ? 0
        : root.pointer.x < root.pointerPlane.x ? -1
        : root.pointer.x > root.pointerPlane.x + root.pointerPlane.width ? 1 : 0
    onPointerScreenNameChanged: {
        if (!root.ownsDrag || root.phase !== "drag")
            return;
        GlobalStates.realGnomeDragShift = 0;
        GlobalStates.realGnomeDragTargetScreen = root.pointerScreenName;
    }

    readonly property real shrinkEase: root.shrinkT
    readonly property size curSize: Qt.size(
        root.slotRectG.width + (root.shrunk.width - root.slotRectG.width) * root.shrinkEase,
        root.slotRectG.height + (root.shrunk.height - root.slotRectG.height) * root.shrinkEase)
    readonly property rect liveRect: Qt.rect(
        root.pointer.x - root.grabFrac.x * root.curSize.width,
        root.pointer.y - root.grabFrac.y * root.curSize.height,
        root.curSize.width, root.curSize.height)
    // Springing back eases the rect from where it was let go to its slot; landing
    // elsewhere shrinks it a little as it fades.
    readonly property rect proxyRect: {
        if (root.phase === "return") {
            const t = root.returnT;
            const r = root.releaseRect, s = root.slotRectG;
            return Qt.rect(r.x + (s.x - r.x) * t, r.y + (s.y - r.y) * t,
                r.width + (s.width - r.width) * t, r.height + (s.height - r.height) * t);
        }
        if (root.phase === "drop") {
            const k = 1 - 0.14 * root.dropT;
            const r = root.liveRect;
            return Qt.rect(r.x + r.width * (1 - k) / 2, r.y + r.height * (1 - k) / 2, r.width * k, r.height * k);
        }
        return root.liveRect;
    }
    onProxyRectChanged: {
        if (root.ownsDrag)
            GlobalStates.realGnomeDragRect = root.proxyRect;
    }
    onDropTChanged: {
        if (root.ownsDrag && root.phase === "drop")
            GlobalStates.realGnomeDragOpacity = 1 - root.dropT;
    }

    readonly property int animDuration: Math.round(Math.max(1, Math.min(10, Number(Config.options.appearance.appLaunchAnimation.speed) || 4))
        * 55 * Appearance.animMultiplier)

    NumberAnimation {
        id: shrinkAnim
        target: root
        property: "shrinkT"
        from: 0
        to: 1
        duration: root.animDuration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
    }
    NumberAnimation {
        id: returnAnim
        target: root
        property: "returnT"
        from: 0
        to: 1
        duration: root.animDuration + 40
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
        onFinished: root.finishDrag()
    }
    NumberAnimation {
        id: dropAnim
        target: root
        property: "dropT"
        from: 0
        to: 1
        duration: root.animDuration
        easing.type: Easing.OutCubic
        onFinished: root.finishDrag()
    }

    function beginDrag(address, pos, grab, slotRect) {
        GlobalStates.realGnomeHoveredWindow = "";
        GlobalStates.realGnomePressedWindow = "";
        root.dragAddress = address;
        root.slotRectG = slotRect;
        root.grabFrac = grab;
        root.pointer = pos;
        // GNOME shrinks the held window to a handy size, growing the gap smoothly.
        const factor = Math.min(1, 320 / Math.max(1, slotRect.width));
        root.shrunk = Qt.size(slotRect.width * factor, slotRect.height * factor);
        root.shrinkT = 0;
        root.returnT = 0;
        root.dropT = 0;
        root.phase = "drag";
        GlobalStates.realGnomeDraggedWindow = address;
        GlobalStates.realGnomeDragOpacity = 1;
        GlobalStates.realGnomeDragRect = root.proxyRect;
        GlobalStates.realGnomeDragTargetScreen = root.screenName;
        GlobalStates.realGnomeDragShift = 0;
        GlobalStates.realGnomeDragPhase = "drag";
        if (transitionAnimationsOff())
            root.shrinkT = 1;
        else
            shrinkAnim.restart();
    }
    function transitionAnimationsOff() {
        return Config.options.overview.animationStyle === "none";
    }
    function moveDrag(pos) {
        root.pointer = pos;
    }
    function startReturn() {
        root.releaseRect = root.liveRect;
        root.phase = "return";
        GlobalStates.realGnomeDragPhase = "return";
        GlobalStates.realGnomeDragTargetScreen = "";
        GlobalStates.realGnomeDragShift = 0;
        if (root.transitionAnimationsOff()) {
            root.returnT = 1;
            root.finishDrag();
        } else {
            returnAnim.restart();
        }
    }
    function startDrop() {
        root.phase = "drop";
        GlobalStates.realGnomeDragPhase = "drop";
        if (root.transitionAnimationsOff()) {
            root.dropT = 1;
            root.finishDrag();
        } else {
            dropAnim.restart();
        }
    }
    function finishDrag() {
        shrinkAnim.stop();
        returnAnim.stop();
        dropAnim.stop();
        root.dragAddress = "";
        root.phase = "";
        GlobalStates.realGnomeDragPhase = "";
        GlobalStates.realGnomeDraggedWindow = "";
        GlobalStates.realGnomeDragOpacity = 1;
    }
    // Torn down without ceremony: the overview closed or the item went away.
    function abortDrag() {
        if (!root.ownsDrag)
            return;
        dwellTimer.stop();
        root.finishDrag();
        GlobalStates.realGnomeDragTargetScreen = "";
        GlobalStates.realGnomeDragShift = 0;
    }
    function endDrag(dropped) {
        if (!root.ownsDrag || root.phase !== "drag")
            return;
        dwellTimer.stop();
        const address = root.dragAddress;
        const target = root.pointerScreenName;
        const targetActive = root.activeWsOf(target);
        const shift = GlobalStates.realGnomeDragTargetScreen === target ? GlobalStates.realGnomeDragShift : 0;
        const side = root.edgeSide;
        if (!dropped || target === "") {
            root.startReturn();
            return;
        }
        if (shift !== 0 && targetActive + shift >= 1) {
            // The strip is already on that workspace: move there and switch for real.
            const ws = targetActive + shift;
            GlobalStates.realGnomeDragCommitScreen = target;
            GlobalStates.realGnomeDragCommitWs = ws;
            Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${ws}, follow = false, window = "address:${address}" })`);
            Hyprland.dispatch(`hl.dsp.focus({ workspace = ${ws} })`);
            root.startDrop();
            return;
        }
        GlobalStates.realGnomeDragShift = 0;
        GlobalStates.realGnomeDragTargetScreen = "";
        if (target !== root.screenName) {
            // Another monitor: onto the workspace it shows (or the neighbour it was dropped beside).
            const ws = side !== 0 && targetActive + side >= 1 ? targetActive + side : targetActive;
            Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${ws}, follow = false, window = "address:${address}" })`);
            root.startDrop();
        } else if (side !== 0 && targetActive + side >= 1) {
            Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${targetActive + side}, follow = false, window = "address:${address}" })`);
            root.startDrop();
        } else {
            root.startReturn();
        }
    }
    // Resting at an edge steps the preview one workspace, then one more per beat.
    Timer {
        id: dwellTimer
        interval: 450
        repeat: true
        running: root.ownsDrag && root.phase === "drag" && root.edgeSide !== 0
        onTriggered: {
            const current = GlobalStates.realGnomeDragTargetScreen === root.pointerScreenName ? GlobalStates.realGnomeDragShift : 0;
            const next = current + root.edgeSide;
            if (root.activeWsOf(root.pointerScreenName) + next < 1)
                return;
            GlobalStates.realGnomeDragTargetScreen = root.pointerScreenName;
            GlobalStates.realGnomeDragShift = next;
            dwellTimer.interval = 700;
        }
        onRunningChanged: dwellTimer.interval = 450
    }

    opacity: root.shown ? 1 : 0
    visible: opacity > 0.001
    enabled: root.shown
    Behavior on opacity {
        NumberAnimation {
            duration: Math.round((root.shown ? 220 : 120) * Appearance.animMultiplier)
            easing.type: Easing.OutCubic
        }
    }
    onShownChanged: {
        if (!root.shown) {
            GlobalStates.realGnomeHoveredWindow = "";
            GlobalStates.realGnomePressedWindow = "";
            root.abortDrag();
        }
    }
    Component.onDestruction: {
        GlobalStates.realGnomeHoveredWindow = "";
        GlobalStates.realGnomePressedWindow = "";
        root.abortDrag();
    }

    Repeater {
        model: ScriptModel {
            values: root.slots
            objectProp: "address"
        }

        delegate: Item {
            id: slot
            required property var modelData

            readonly property string address: slot.modelData.address
            readonly property bool hovered: slotHover.hovered && GlobalStates.realGnomeDragPhase === ""
            readonly property string iconSource: {
                const _ = TaskbarApps.iconThemeRevision;
                return Quickshell.iconPath(AppSearch.guessIcon(slot.modelData.appClass), "image-missing");
            }

            x: slot.modelData.x + root.offsetX
            y: slot.modelData.y + root.offsetY
            width: slot.modelData.width
            height: slot.modelData.height

            HoverHandler {
                id: slotHover
                onHoveredChanged: {
                    if (GlobalStates.realGnomeDragPhase !== "")
                        return;
                    if (slotHover.hovered)
                        GlobalStates.realGnomeHoveredWindow = slot.address;
                    else if (GlobalStates.realGnomeHoveredWindow === slot.address)
                        GlobalStates.realGnomeHoveredWindow = "";
                }
            }

            // The dragged window leaves its slot (the capture hides too).
            opacity: GlobalStates.realGnomeDraggedWindow === slot.address ? 0 : 1
            Component.onDestruction: {
                if (root.dragAddress === slot.address)
                    root.abortDrag();
            }

            MouseArea {
                id: slotMouse
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                cursorShape: GlobalStates.realGnomeDragPhase === "drag" ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                property point pressPoint: Qt.point(0, 0)
                property bool moved: false
                // Screen -> global (layout) coordinates for a point in this picker.
                function toGlobal(pos) {
                    return Qt.point(root.screenX + pos.x - root.offsetX, root.screenY + pos.y - root.offsetY);
                }
                onPressed: mouse => {
                    slotMouse.pressPoint = Qt.point(mouse.x, mouse.y);
                    slotMouse.moved = false;
                    if (mouse.button === Qt.LeftButton)
                        GlobalStates.realGnomePressedWindow = slot.address;
                }
                onPositionChanged: mouse => {
                    if (!(slotMouse.pressedButtons & Qt.LeftButton))
                        return;
                    const pos = slotMouse.toGlobal(slotMouse.mapToItem(root, mouse.x, mouse.y));
                    if (!slotMouse.moved) {
                        const dx = mouse.x - slotMouse.pressPoint.x;
                        const dy = mouse.y - slotMouse.pressPoint.y;
                        if (dx * dx + dy * dy < 64)
                            return;
                        slotMouse.moved = true;
                        const origin = slotMouse.toGlobal(slotMouse.mapToItem(root, 0, 0));
                        root.beginDrag(slot.address, pos,
                            Qt.point(slotMouse.pressPoint.x / Math.max(1, slot.width), slotMouse.pressPoint.y / Math.max(1, slot.height)),
                            Qt.rect(origin.x, origin.y, slot.width, slot.height));
                    }
                    root.moveDrag(pos);
                }
                onReleased: {
                    if (GlobalStates.realGnomePressedWindow === slot.address)
                        GlobalStates.realGnomePressedWindow = "";
                    if (slotMouse.moved)
                        root.endDrag(true);
                }
                onCanceled: {
                    if (GlobalStates.realGnomePressedWindow === slot.address)
                        GlobalStates.realGnomePressedWindow = "";
                    if (slotMouse.moved)
                        root.endDrag(false);
                }
                onClicked: mouse => {
                    if (slotMouse.moved)
                        return;
                    if (mouse.button === Qt.MiddleButton) {
                        Hyprland.dispatch(`hl.dsp.window.close({ window = "address:${slot.address}" })`);
                        return;
                    }
                    Hyprland.dispatch(`hl.dsp.focus({ window = "address:${slot.address}" })`);
                    GlobalStates.overviewOpen = false;
                }
            }

            // App icon straddling the bottom edge, always shown.
            IconImage {
                id: appIcon
                readonly property real size: Math.round(Math.max(28, Math.min(48, slot.height * 0.22)))
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.bottom
                implicitSize: appIcon.size
                source: slot.iconSource
                scale: slot.hovered ? 1.08 : 1.0
                Behavior on scale {
                    NumberAnimation { duration: Math.round(200 * Appearance.animMultiplier); easing.type: Easing.OutCubic }
                }
            }

            // Title under the icon on hover.
            Rectangle {
                id: titleChip
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: appIcon.bottom
                anchors.topMargin: 6
                width: Math.min(Math.max(slot.width, 160), titleText.implicitWidth + 24)
                height: titleText.implicitHeight + 10
                radius: height / 2
                color: Appearance.m3colors.m3surfaceContainerHighest
                opacity: slot.hovered && slot.modelData.title.length > 0 ? 1 : 0
                visible: opacity > 0.001
                Behavior on opacity {
                    NumberAnimation { duration: Math.round(160 * Appearance.animMultiplier); easing.type: Easing.OutCubic }
                }

                StyledText {
                    id: titleText
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, titleChip.width - 24)
                    text: slot.modelData.title
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.m3colors.m3onSurface
                }
            }

            // Close button in the top-right corner on hover.
            RippleButton {
                id: closeButton
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: -width / 3
                anchors.topMargin: -height / 3
                implicitWidth: 30
                implicitHeight: 30
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.m3colors.m3surfaceContainerHighest
                colBackgroundHover: Appearance.m3colors.m3surfaceContainerHighest
                opacity: slot.hovered ? 1 : 0
                visible: opacity > 0.001
                scale: slot.hovered ? 1 : 0.8
                Behavior on opacity {
                    NumberAnimation { duration: Math.round(160 * Appearance.animMultiplier); easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    NumberAnimation { duration: Math.round(200 * Appearance.animMultiplier); easing.type: Easing.OutCubic }
                }
                onClicked: Hyprland.dispatch(`hl.dsp.window.close({ window = "address:${slot.address}" })`)

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: "close"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.m3colors.m3onSurface
                }
            }
        }
    }

    // The held window under the pointer, on whichever monitor it is over.
    RealGnomeDragProxy {
        screenName: root.screenName
        offsetX: root.offsetX
        offsetY: root.offsetY
    }
}
