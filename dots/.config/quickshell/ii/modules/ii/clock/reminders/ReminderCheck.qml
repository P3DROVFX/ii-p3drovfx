import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Samsung Reminder's completion circle: a soft tint of the category's colour, filled
 * solid with a check once done. The tint deepens and the check shows faintly under the
 * pointer to say what a click will do. Fills, not an outline (guide §0).
 */
Item {
    id: root

    property bool checked: false
    property color colAccent: ClockStyle.colPrimary
    property real size: 26
    property string tooltip: ""

    signal toggled()

    implicitWidth: root.size + 10
    implicitHeight: root.size + 10

    Rectangle {
        id: ring
        anchors.centerIn: parent
        width: root.size
        height: root.size
        radius: width / 2
        color: root.checked ? root.colAccent
            : ColorUtils.applyAlpha(root.colAccent, pointer.containsMouse ? 0.28 : 0.16)
        // The sanctioned press response (guide §8.2), nothing bigger.
        scale: pointer.pressed ? 0.95 : 1

        Behavior on color {
            enabled: !ClockStyle.reducedMotion
            animation: ClockStyle.motionFast.colorAnimation.createObject(this)
        }
        Behavior on scale {
            enabled: !ClockStyle.reducedMotion
            animation: ClockStyle.motionFast.numberAnimation.createObject(this)
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: "check"
            iconSize: root.size * 0.7
            fill: 1
            color: root.checked ? RemindersStyle.onColor(root.colAccent) : root.colAccent
            opacity: root.checked ? 1 : pointer.containsMouse ? 0.9 : 0
            Behavior on opacity {
                enabled: !ClockStyle.reducedMotion
                animation: ClockStyle.motionFast.numberAnimation.createObject(this)
            }
        }
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }

    StyledToolTip {
        text: root.tooltip
        extraVisibleCondition: root.tooltip.length > 0 && pointer.containsMouse
    }
}
