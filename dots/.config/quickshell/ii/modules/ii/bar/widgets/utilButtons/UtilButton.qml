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

    readonly property real baseSize: (vertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.baseBarHeight) - 14
    implicitWidth: vertical ? baseSize : (hovered ? baseSize + 28 : baseSize)
    implicitHeight: vertical ? (hovered ? baseSize + 28 : baseSize) : baseSize

    property bool hovered: mouseArea.containsMouse || forceHovered

    readonly property int animDuration: Math.round(120 * Appearance.animMultiplier)

    Behavior on implicitWidth {
        NumberAnimation {
            duration: root.animDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.34, 0.80, 0.34, 1.00, 1, 1]
        }
    }

    Behavior on implicitHeight {
        NumberAnimation {
            duration: root.animDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.34, 0.80, 0.34, 1.00, 1, 1]
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.full
        color: root.hovered ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colOnPrimaryContainer, 0.88)

        Behavior on color {
            ColorAnimation { duration: root.animDuration }
        }
        Behavior on opacity {
            NumberAnimation { duration: root.animDuration }
        }

        MaterialSymbol {
            id: symbol
            anchors.centerIn: parent
            iconSize: Appearance.font.pixelSize.large
            color: root.hovered ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer

            Behavior on color {
                ColorAnimation { duration: root.animDuration }
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