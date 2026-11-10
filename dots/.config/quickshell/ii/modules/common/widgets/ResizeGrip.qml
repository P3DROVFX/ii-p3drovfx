import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * The desktop's corner resize grip: a small tonal square with the
 * open_in_full glyph, primary while hovered or held. Shared by the
 * background widgets and the launch-pad cards so the two resize the same
 * way to the eye; what a drag does is the host's (the pointer events are
 * passed on as they arrive).
 *
 * Anchor it to the host's bottom-right corner. The grip is drawn inside the
 * host; the hit area hangs off the corner, which is what makes it grabbable.
 */
Item {
    id: root

    // Whether the host offers the grip right now (hover, the mode, ...).
    property bool shown: false
    // Rasterises the glyph at the size it is shown at, when the host draws
    // itself scaled.
    property real renderScale: 1
    readonly property bool active: area.pressed
    readonly property bool hovered: area.containsMouse

    signal pressed(var mouse)
    signal positionChanged(var mouse)
    signal released(var mouse)
    signal canceled()
    signal doubleClicked(var mouse)

    visible: opacity > 0.001
    // Shown on hover, and throughout the mode: a grip you have to find by
    // hovering is not an affordance in a layout editor.
    opacity: root.shown || root.active ? 1 : 0
    // Grow into place instead of only fading: at this size a pure opacity
    // ramp reads as a glitch rather than as something arriving.
    scale: opacity > 0.5 ? 1 : 0.7
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }
    Behavior on scale {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(root)
    }
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.rightMargin: -6
    anchors.bottomMargin: -6
    width: 40
    height: 40
    z: 99

    Rectangle {
        id: grip
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: -3
        anchors.verticalCenterOffset: -3
        width: 22
        height: 22
        radius: 7
        color: root.active || root.hovered
            ? Appearance.colors.colPrimary
            : Appearance.colors.colSecondaryContainer

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(grip)
        }

        // Rasterised at the size it is shown at: the glyph is a native-
        // rendered bitmap, and the host's own scale only stretched it.
        MaterialSymbol {
            anchors.centerIn: parent
            text: "open_in_full"
            iconSize: 13 * root.renderScale
            scale: 1 / root.renderScale
            font.variableAxes: ({ "FILL": 0, "wght": 400, "opsz": 20 })
            color: root.active || root.hovered
                ? Appearance.colors.colOnPrimary
                : Appearance.colors.colOnSecondaryContainer
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.SizeFDiagCursor
        preventStealing: true

        onPressed: mouse => root.pressed(mouse)
        onPositionChanged: mouse => root.positionChanged(mouse)
        onReleased: mouse => root.released(mouse)
        onCanceled: root.canceled()
        onDoubleClicked: mouse => root.doubleClicked(mouse)
    }
}
