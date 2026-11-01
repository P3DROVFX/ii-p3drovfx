import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * One of the three queue counts. The queue the shown card came from fills with its
 * colour and its digits gain weight; the others rest on the pane.
 */
Rectangle {
    id: root

    property string label: ""
    property int value: 0
    property bool current: false
    property color colActive: ClockStyle.colPrimaryContainer
    property color colOnActive: ClockStyle.colOnPrimaryContainer

    implicitHeight: 44
    radius: root.current ? Appearance.rounding.normal : Appearance.rounding.full
    color: root.current ? root.colActive : ClockStyle.colPane

    Behavior on radius {
        enabled: !ClockStyle.reducedMotion
        animation: ClockStyle.motionFast.numberAnimation.createObject(this)
    }
    Behavior on color {
        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
    }

    // Two fixed axis sets, not an animated weight: every distinct wght/wdth is a new
    // font face in memory.
    readonly property real boldness: root.current ? 1 : 0

    RowLayout {
        anchors.centerIn: parent
        spacing: 6

        StyledText {
            text: root.value
            font.family: ClockStyle.fontMain
            font.variableAxes: ({
                "wght": Math.round(560 + 200 * root.boldness),
                "wdth": Math.round(30 + 10 * root.boldness),
                "ROND": 100
            })
            font.pixelSize: Appearance.font.pixelSize.hugeass
            color: root.current ? root.colOnActive : ClockStyle.colOnSurface
        }
        StyledText {
            text: root.label
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.Bold
            color: root.current ? root.colOnActive : ClockStyle.colOnSurfaceVariant
        }
    }
}
