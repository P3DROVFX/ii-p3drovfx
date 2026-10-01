import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Samsung Reminder's completion circle: an outline in the category's colour, filled with
 * a check once done. The ring fills under the pointer to say what a click will do.
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
            : pointer.containsMouse ? ColorUtils.applyAlpha(root.colAccent, 0.22) : "transparent"
        border.width: root.checked ? 0 : 2
        border.color: root.colAccent
        scale: pointer.pressed ? 0.86 : 1

        Behavior on color {
            animation: ClockStyle.motionFast.colorAnimation.createObject(this)
        }
        Behavior on scale {
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
