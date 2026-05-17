import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.models
import qs.modules.common.functions

Item {
    id: root
    signal clicked(event: var)
    property bool vertical: false
    property alias iconText: symbol.text
    property bool isActive: false
    property bool forceHovered: false

    readonly property real baseSize: (vertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight) - 14
    implicitWidth: vertical ? baseSize : (hovered ? baseSize + 28 : baseSize)
    implicitHeight: vertical ? (hovered ? baseSize + 28 : baseSize) : baseSize

    property bool hovered: mouseArea.containsMouse || forceHovered

    Behavior on implicitWidth {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.easing
        }
    }

    Behavior on implicitHeight {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.easing
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.full
        color: root.hovered ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colLayer0, 0.8)

        Behavior on color {
            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
        }
        Behavior on opacity {
            NumberAnimation { duration: Appearance.animation.elementMoveFast.duration }
        }

        MaterialSymbol {
            id: symbol
            anchors.centerIn: parent
            iconSize: Appearance.font.pixelSize.large
            color: root.hovered ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary

            Behavior on color {
                ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: (e) => root.clicked(e)
    }
}