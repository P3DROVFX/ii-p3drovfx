import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick

RippleButton {
    id: root
    required property var element
    implicitHeight: 70
    implicitWidth: 70
    colBackground: Appearance.colors.colLayer2
    buttonRadius: Appearance.rounding.small

    property int tileIndex: 0
    property bool tileAnimatedIn: false

    opacity: element.type != "empty" ? (tileAnimatedIn ? 1.0 : 0.0) : 0.0

    transform: Scale {
        id: tileScale
        origin.x: 35
        origin.y: 35
        xScale: root.tileAnimatedIn ? (root.isHovered ? 1.08 : 1.0) : 0.6
        yScale: root.tileAnimatedIn ? (root.isHovered ? 1.08 : 1.0) : 0.6
    }

    Component.onCompleted: {
        tileTimer.start();
    }

    Timer {
        id: tileTimer
        interval: Math.min((tileIndex % 18) * 15, 320)
        repeat: false
        onTriggered: root.tileAnimatedIn = true
    }

    Behavior on opacity {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
        }
    }

    Rectangle {
        anchors {
            top: parent.top
            left: parent.left
            topMargin: 4
            leftMargin: 4
        }
        color: ColorUtils.transparentize(Appearance.colors.colLayer2)
        radius: Appearance.rounding.full
        implicitWidth: Math.max(20, elementNumber.implicitWidth)
        implicitHeight: Math.max(20, elementNumber.implicitHeight)
        width: height

        StyledText {
            id: elementNumber
            anchors.left: parent.left
            color: Appearance.colors.colOnLayer2
            text: root.element.number
            font.pixelSize: Appearance.font.pixelSize.smallest
        }
    }

    Rectangle {
        anchors {
            top: parent.top
            right: parent.right
            topMargin: 4
            rightMargin: 4
        }
        color: ColorUtils.transparentize(Appearance.colors.colLayer2)
        radius: Appearance.rounding.full
        implicitWidth: Math.max(20, elementWeight.implicitWidth)
        implicitHeight: Math.max(20, elementWeight.implicitHeight)
        width: height

        StyledText {
            id: elementWeight
            anchors.right: parent.right
            color: Appearance.colors.colOnLayer2
            text: root.element.weight
            font.pixelSize: Appearance.font.pixelSize.smallest
        }
    }

    StyledText {
        id: elementSymbol
        anchors.centerIn: parent
        color: Appearance.colors.colSecondary
        font.pixelSize: Appearance.font.pixelSize.huge
        text: root.element.symbol
    }

    StyledText {
        id: elementName
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: 4
        }
        font.pixelSize: Appearance.font.pixelSize.smallest
        color: Appearance.colors.colOnLayer2
        text: root.element.name
    }
}
