import qs.modules.common
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property bool vertical: false
    property real padding: 5
    property real leftPadding: padding
    property real rightPadding: padding
    property real topPadding: padding
    property real bottomPadding: padding

    implicitWidth: vertical ? Appearance.sizes.baseVerticalBarWidth : (gridLayout.implicitWidth + leftPadding + rightPadding)
    implicitHeight: vertical ? (gridLayout.implicitHeight + topPadding + bottomPadding) : Appearance.sizes.baseBarHeight
    default property alias items: gridLayout.children
    property var startRadius // left - top
    property var endRadius // right - bottom

    property color colBackground: Appearance.m3colors.m3surfaceContainerLow

    Rectangle {
        id: background
        anchors {
            fill: parent
            topMargin: root.vertical ? 0 : 4
            bottomMargin: root.vertical ? 0 : 4
            leftMargin: root.vertical ? 4 : 0
            rightMargin: root.vertical ? 4 : 0
        }
        color: root.colBackground
        topLeftRadius: startRadius
        bottomLeftRadius: root.vertical ? endRadius: startRadius
        topRightRadius: root.vertical ? startRadius: endRadius
        bottomRightRadius: endRadius

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    GridLayout {
        id: gridLayout
        columns: root.vertical ? 1 : -1
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: root.vertical ? undefined : parent.left
            right: root.vertical ? undefined : parent.right
            horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
            topMargin: root.topPadding
            bottomMargin: root.bottomPadding
            leftMargin: root.leftPadding
            rightMargin: root.rightPadding
        }
        columnSpacing: 4
        rowSpacing: 12
    }
}