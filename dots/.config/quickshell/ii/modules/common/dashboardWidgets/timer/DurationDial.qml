import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * One unit of the countdown picker. Drag up/down or scroll over it to change
 * the value; the hover arrows do single steps for pointer users who don't
 * discover the drag.
 */
Item {
    id: dial
    property string unitLabel: ""
    property int value: 0
    property int maxValue: 59
    // Vertical travel, in pixels, worth one unit.
    property real dragStep: 9
    // Vertical slack, in pixels, that still counts as a tap rather than a drag.
    property real tapSlop: 4
    property real numberSize: 32
    property bool interactive: true
    signal valueRequested(int newValue)

    implicitWidth: 62
    implicitHeight: 66

    readonly property bool active: dragArea.containsMouse || dragArea.pressed

    function step(delta) {
        if (delta === 0 || !dial.interactive)
            return;
        const span = dial.maxValue + 1;
        const next = ((dial.value + delta) % span + span) % span;
        if (next !== dial.value)
            dial.valueRequested(next);
    }

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.small
        color: dial.active ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: -2

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: String(dial.value).padStart(2, '0')
            font.pixelSize: dial.numberSize
            color: Appearance.m3colors.m3onSurface
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: dial.unitLabel
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }

    // One gesture handler for both interactions: dragging anywhere scrubs the
    // value, and a tap that never moved steps once, in the direction of the
    // half of the dial it landed on. Separate arrow buttons fought the drag.
    MouseArea {
        id: dragArea
        anchors.fill: parent
        enabled: dial.interactive
        hoverEnabled: true
        cursorShape: Qt.SizeVerCursor
        acceptedButtons: Qt.LeftButton

        property real accumulated: 0
        property real lastY: 0
        property real travelled: 0
        property real pressY: 0

        onPressed: event => {
            dragArea.lastY = event.y;
            dragArea.pressY = event.y;
            dragArea.accumulated = 0;
            dragArea.travelled = 0;
        }
        onPositionChanged: event => {
            if (!dragArea.pressed)
                return;
            // Up is negative in item coordinates, but should raise the value.
            const delta = dragArea.lastY - event.y;
            dragArea.lastY = event.y;
            dragArea.accumulated += delta;
            dragArea.travelled += Math.abs(delta);
            const steps = Math.trunc(dragArea.accumulated / dial.dragStep);
            if (steps === 0)
                return;
            dragArea.accumulated -= steps * dial.dragStep;
            dial.step(steps);
        }
        onReleased: {
            if (dragArea.travelled > dial.tapSlop)
                return;
            dial.step(dragArea.pressY < dial.height / 2 ? 1 : -1);
        }
        onWheel: event => dial.step(event.angleDelta.y > 0 ? 1 : -1)
    }

    // Purely decorative: the whole dial is the hit area, these only show which
    // half does what.
    Loader {
        anchors.fill: parent
        active: dial.interactive && dial.active
        sourceComponent: Item {
            ArrowHint {
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                arrow: "keyboard_arrow_up"
                highlighted: dragArea.containsMouse && dragArea.mouseY < dial.height / 2
            }
            ArrowHint {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                arrow: "keyboard_arrow_down"
                highlighted: dragArea.containsMouse && dragArea.mouseY >= dial.height / 2
            }
        }
    }

    component ArrowHint: Item {
        id: arrowHint
        property string arrow: ""
        property bool highlighted: false

        implicitWidth: 20
        implicitHeight: 16

        MaterialSymbol {
            anchors.centerIn: parent
            text: arrowHint.arrow
            iconSize: Appearance.font.pixelSize.normal
            color: arrowHint.highlighted ? Appearance.colors.colPrimary : Appearance.colors.colSubtext

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }
}
