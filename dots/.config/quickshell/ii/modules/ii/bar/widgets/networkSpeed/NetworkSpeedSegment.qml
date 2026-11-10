import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * One filled segment of the split design: a single direction on its own
 * surface. `startRadius` is the leading end (left, or top when vertical) and
 * `endRadius` the trailing one, so a pair of segments can meet with small
 * corners in the middle and round ones outside.
 */
Rectangle {
    id: root

    property var net
    property var rate
    property bool vertical: false
    property string iconName: "arrow_downward"
    property real thickness: 32
    property real startRadius: Appearance.rounding.full
    property real endRadius: Appearance.rounding.full
    property color fg: Appearance.colors.colOnLayer1

    implicitWidth: root.vertical ? root.thickness : cell.implicitWidth + root.net.tight(22, 14)
    implicitHeight: root.vertical ? cell.implicitHeight + root.net.tight(14, 8) : root.thickness

    topLeftRadius: root.startRadius
    bottomLeftRadius: root.vertical ? root.endRadius : root.startRadius
    topRightRadius: root.vertical ? root.startRadius : root.endRadius
    bottomRightRadius: root.endRadius

    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }
    Behavior on startRadius {
        NumberAnimation {
            duration: Math.round(200 * Appearance.animMultiplier)
            easing.type: Easing.OutQuad
        }
    }
    Behavior on endRadius {
        NumberAnimation {
            duration: Math.round(200 * Appearance.animMultiplier)
            easing.type: Easing.OutQuad
        }
    }

    NetworkSpeedCell {
        id: cell

        anchors.centerIn: parent
        vertical: root.vertical
        readout: root.net
        rate: root.rate
        iconName: root.iconName
        iconColor: root.fg
        numberColor: root.fg
        unitColor: ColorUtils.mix(root.fg, root.color, 0.75)
    }
}
