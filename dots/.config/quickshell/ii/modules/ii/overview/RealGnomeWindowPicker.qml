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

    // ── Drag to another workspace ───────────────────────────────────────────
    // A held window follows the pointer; resting it at the plane's side edge
    // previews the neighbouring workspace by sliding the strip (a real switch
    // would end the drag - Hyprland releases a held pointer on a focus change).
    // Dropping moves the window to the workspace in the middle and switches
    // there; dropping straight onto a neighbour beside the plane only moves it.
    property string dragAddress: ""
    property point dragPos: Qt.point(0, 0)
    property point dragGrab: Qt.point(0, 0)
    property size dragSize: Qt.size(0, 0)
    readonly property bool dragging: root.dragAddress !== ""
    readonly property var monitor: Hyprland.monitors.values.find(m => m.name === root.screenName) ?? null
    readonly property int activeWs: Math.max(1, root.monitor?.activeWorkspace?.id ?? 1)
    readonly property rect plane: {
        const t = root.controller ? root.controller.realGnomeTarget : Qt.rect(0, 0, 0, 0);
        return Qt.rect(t.x + root.offsetX, t.y + root.offsetY, t.width, t.height);
    }
    readonly property int edgeSide: !root.dragging || root.plane.width <= 0 ? 0
        : root.dragPos.x < root.plane.x ? -1
        : root.dragPos.x > root.plane.x + root.plane.width ? 1 : 0
    readonly property var dragToplevel: {
        if (!root.dragging)
            return null;
        return (ToplevelManager.toplevels.values ?? []).find(toplevel => {
            const raw = String(toplevel?.HyprlandToplevel?.address ?? "");
            const key = raw.toLowerCase().indexOf("0x") === 0 ? "0x" + raw.slice(2) : "0x" + raw;
            return key === root.dragAddress;
        }) ?? null;
    }

    function beginDrag(address, pos, grab, size) {
        GlobalStates.realGnomeHoveredWindow = "";
        clearDraggedTimer.stop();
        root.dragAddress = address;
        root.dragGrab = grab;
        root.dragSize = size;
        root.dragPos = pos;
        GlobalStates.realGnomeDraggedWindow = address;
    }
    function moveDrag(pos) {
        root.dragPos = pos;
    }
    function endDrag(dropped) {
        if (!root.dragging)
            return;
        const address = root.dragAddress;
        const shift = GlobalStates.realGnomeDragShift;
        const side = root.edgeSide;
        root.dragAddress = "";
        dwellTimer.stop();
        if (dropped && shift !== 0) {
            const target = root.activeWs + shift;
            GlobalStates.realGnomeDragCommitWs = target;
            Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${target}, follow = false, window = "address:${address}" })`);
            Hyprland.dispatch(`hl.dsp.focus({ workspace = ${target} })`);
        } else {
            if (dropped && side !== 0 && root.activeWs + side >= 1)
                Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${root.activeWs + side}, follow = false, window = "address:${address}" })`);
            GlobalStates.realGnomeDragShift = 0;
        }
        // The window leaves its slot a moment after the dispatch; showing the
        // tile again at once would flash it where it was.
        clearDraggedTimer.restart();
    }
    Timer {
        id: clearDraggedTimer
        interval: 160
        onTriggered: GlobalStates.realGnomeDraggedWindow = ""
    }
    // Resting at an edge steps the preview one workspace, then one more per beat.
    Timer {
        id: dwellTimer
        interval: 450
        repeat: true
        running: root.dragging && root.edgeSide !== 0
        onTriggered: {
            const next = GlobalStates.realGnomeDragShift + root.edgeSide;
            if (root.activeWs + next < 1)
                return;
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
            root.endDrag(false);
        }
    }
    Component.onDestruction: {
        GlobalStates.realGnomeHoveredWindow = "";
        if (root.dragging) {
            GlobalStates.realGnomeDraggedWindow = "";
            GlobalStates.realGnomeDragShift = 0;
        }
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
            readonly property bool hovered: slotHover.hovered && !root.dragging
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
                    if (root.dragging)
                        return;
                    if (slotHover.hovered)
                        GlobalStates.realGnomeHoveredWindow = slot.address;
                    else if (GlobalStates.realGnomeHoveredWindow === slot.address)
                        GlobalStates.realGnomeHoveredWindow = "";
                }
            }

            // The dragged window leaves its slot (the capture hides too).
            opacity: root.dragAddress === slot.address ? 0 : 1
            Component.onDestruction: {
                if (root.dragAddress === slot.address)
                    root.endDrag(false);
            }

            MouseArea {
                id: slotMouse
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                property point pressPoint: Qt.point(0, 0)
                property bool moved: false
                onPressed: mouse => {
                    slotMouse.pressPoint = Qt.point(mouse.x, mouse.y);
                    slotMouse.moved = false;
                }
                onPositionChanged: mouse => {
                    if (!(slotMouse.pressedButtons & Qt.LeftButton))
                        return;
                    const pos = slotMouse.mapToItem(root, mouse.x, mouse.y);
                    if (!slotMouse.moved) {
                        const dx = mouse.x - slotMouse.pressPoint.x;
                        const dy = mouse.y - slotMouse.pressPoint.y;
                        if (dx * dx + dy * dy < 64)
                            return;
                        slotMouse.moved = true;
                        // GNOME shrinks the held window to a handy size.
                        const factor = Math.min(1, 320 / Math.max(1, slot.width));
                        root.beginDrag(slot.address, pos,
                            Qt.point(slotMouse.pressPoint.x * factor, slotMouse.pressPoint.y * factor),
                            Qt.size(slot.width * factor, slot.height * factor));
                    }
                    root.moveDrag(pos);
                }
                onReleased: {
                    if (slotMouse.moved)
                        root.endDrag(true);
                }
                onCanceled: {
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

    // The held window under the pointer.
    Item {
        id: dragProxy
        visible: root.dragging
        x: root.dragPos.x - root.dragGrab.x
        y: root.dragPos.y - root.dragGrab.y
        width: root.dragSize.width
        height: root.dragSize.height

        StyledRectangularShadow {
            target: dragCapture
            blur: 28
            opacity: 0.45
            offset: Qt.vector2d(0, 6)
        }
        Item {
            id: dragCapture
            anchors.fill: parent
            layer.enabled: true
            layer.effect: OverviewRoundedMask {
                cornerRadius: Appearance.rounding.windowRounding
            }
            ScreencopyView {
                anchors.fill: parent
                captureSource: root.dragging ? root.dragToplevel : null
                live: true
                paintCursor: false
            }
        }
    }
}
