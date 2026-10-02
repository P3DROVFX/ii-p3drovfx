import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * A filter over a list ("Music 3"): dashed and empty until chosen, filled with the
 * secondary container once it is, with the count in a small badge on its end. The
 * timetable rail's choice chip, sized for a page toolbar.
 */
Rectangle {
    id: root

    property string label: ""
    property string symbol: ""
    property int count: -1
    property bool selected: false

    signal triggered()

    implicitWidth: chipRow.implicitWidth + EasyEffectsStyle.gapLarge * 2
    implicitHeight: EasyEffectsStyle.chipHeight
    radius: EasyEffectsStyle.radiusChip
    color: root.selected ? EasyEffectsStyle.colSecondaryContainer
        : pointer.containsMouse ? EasyEffectsStyle.tint(EasyEffectsStyle.colPrimary, EasyEffectsStyle.tintIdle) : "transparent"

    Behavior on color {
        animation: EasyEffectsStyle.motionFast.colorAnimation.createObject(this)
    }

    DashedBorder {
        anchors.fill: parent
        visible: !root.selected
        color: EasyEffectsStyle.tint(EasyEffectsStyle.colSubtext, EasyEffectsStyle.tintDash)
        borderWidth: 1
        dashLength: 4
        gapLength: 3
        radius: root.radius
    }

    RowLayout {
        id: chipRow
        anchors.centerIn: parent
        spacing: EasyEffectsStyle.gapSmall - 2

        MaterialSymbol {
            visible: root.symbol.length > 0 || root.selected
            text: root.selected ? "check" : root.symbol
            iconSize: EasyEffectsStyle.iconSmall
            color: root.selected ? EasyEffectsStyle.colOnSecondaryContainer : EasyEffectsStyle.colOnSurfaceVariant
        }

        StyledText {
            text: root.label
            font.pixelSize: EasyEffectsStyle.textNormal
            font.weight: Font.Medium
            color: root.selected ? EasyEffectsStyle.colOnSecondaryContainer : EasyEffectsStyle.colOnSurfaceVariant
        }

        Rectangle {
            visible: root.count >= 0
            implicitWidth: Math.max(EasyEffectsStyle.tabCountBadge, countText.implicitWidth + EasyEffectsStyle.gapSmall * 1.5)
            implicitHeight: EasyEffectsStyle.tabCountBadge
            radius: height / 2
            color: root.selected ? EasyEffectsStyle.colPrimary : EasyEffectsStyle.colField

            StyledText {
                id: countText
                anchors.centerIn: parent
                text: String(root.count)
                font.pixelSize: EasyEffectsStyle.textCaption
                font.weight: Font.Bold
                color: root.selected ? EasyEffectsStyle.colOnPrimary : EasyEffectsStyle.colOnSurfaceVariant
            }
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
