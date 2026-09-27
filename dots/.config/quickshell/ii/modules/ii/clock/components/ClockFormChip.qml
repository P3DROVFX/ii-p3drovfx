import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * The timetable rail's quick-choice chip (30m / 1h / Event / Task): dashed and empty
 * until chosen, filled with the secondary container once it is.
 */
Rectangle {
    id: root

    property string label: ""
    property string symbol: ""
    property bool selected: false

    signal triggered()

    implicitWidth: chipRow.implicitWidth + 26
    implicitHeight: 34
    radius: Appearance.rounding.full
    color: root.selected ? ClockStyle.colSecondaryContainer
        : pointer.containsMouse ? ColorUtils.applyAlpha(ClockStyle.colPrimary, 0.08) : "transparent"

    Behavior on color {
        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
    }

    DashedBorder {
        anchors.fill: parent
        visible: !root.selected
        color: ColorUtils.applyAlpha(Appearance.colors.colOutline, 0.8)
        borderWidth: 1
        dashLength: 4
        gapLength: 3
        radius: Appearance.rounding.full
    }

    RowLayout {
        id: chipRow
        anchors.centerIn: parent
        spacing: 5

        MaterialSymbol {
            visible: root.symbol.length > 0
            text: root.symbol
            iconSize: Appearance.font.pixelSize.normal
            fill: root.selected ? 1 : 0
            color: root.selected ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurfaceVariant
        }

        StyledText {
            text: root.label
            font.pixelSize: Appearance.font.pixelSize.smallie
            font.weight: Font.Bold
            color: root.selected ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurfaceVariant
        }
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.triggered()
    }
}
