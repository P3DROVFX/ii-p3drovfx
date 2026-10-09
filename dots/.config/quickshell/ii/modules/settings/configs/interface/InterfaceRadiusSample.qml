import QtQuick
import QtQuick.Layouts
import qs.modules.common

/**
 * What the corner radius does, drawn with the radius itself: a card, a button and a chip
 * take the slider's value in pixels, so the slider's effect is the picture. The corner
 * each shape may reach is capped at half its shortest side.
 */
Rectangle {
    id: root

    readonly property real stageHeight: 120
    readonly property real stagePadding: 18
    readonly property real shapeGap: 14
    readonly property real cardWidth: 124
    readonly property real cardHeight: 84
    readonly property real buttonWidth: 92
    readonly property real buttonHeight: 40
    readonly property real chipSize: 56

    property real radiusValue: 0

    function capped(size) {
        return Math.min(root.radiusValue, size / 2);
    }

    Layout.fillWidth: true
    implicitHeight: root.stageHeight
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2

    Row {
        anchors.centerIn: parent
        spacing: root.shapeGap

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: root.cardWidth
            height: root.cardHeight
            radius: root.capped(height)
            color: Appearance.colors.colPrimaryContainer
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.shapeGap

            Rectangle {
                width: root.buttonWidth
                height: root.buttonHeight
                radius: root.capped(height)
                color: Appearance.colors.colPrimary
            }
            Rectangle {
                width: root.chipSize
                height: root.chipSize - root.buttonHeight
                radius: root.capped(height)
                color: Appearance.colors.colSecondaryContainer
            }
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: root.chipSize
            height: root.chipSize
            radius: root.capped(height)
            color: Appearance.colors.colTertiaryContainer
        }
    }
}
