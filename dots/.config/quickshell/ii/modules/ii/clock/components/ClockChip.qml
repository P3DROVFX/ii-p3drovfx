import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/** Assist / filter chip. Selected chips fill with the secondary container. */
RippleButton {
    id: root

    property string symbol: ""
    property string label: ""
    property bool selected: false
    property real height_: ClockStyle.chipHeight
    property color colIdle: ClockStyle.colSurfaceHigh
    property color colIdleHover: ClockStyle.colSurfaceHover
    property color colOnIdle: ClockStyle.colOnSurfaceVariant
    property color colSelected: ClockStyle.colSecondaryContainer
    property color colSelectedHover: ClockStyle.colSecondaryContainerHover
    property color colOnSelected: ClockStyle.colOnSecondaryContainer

    implicitHeight: root.height_
    implicitWidth: chipRow.implicitWidth + ClockStyle.gapLarge * 2
    buttonRadius: root.selected ? ClockStyle.radiusSmall : ClockStyle.pill(root.height_)
    buttonRadiusPressed: ClockStyle.radiusSmall
    colBackground: root.selected ? root.colSelected : root.colIdle
    colBackgroundHover: root.selected ? root.colSelectedHover : root.colIdleHover
    colRipple: root.selected ? ClockStyle.colSecondaryContainerActive : ClockStyle.colSurfaceActive

    contentItem: Item {
        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: ClockStyle.gapTiny + 2

            MaterialSymbol {
                visible: root.symbol.length > 0
                text: root.symbol
                iconSize: ClockStyle.iconSmall
                fill: root.selected ? 1 : 0
                color: root.selected ? root.colOnSelected : root.colOnIdle
            }

            StyledText {
                text: root.label
                font.pixelSize: ClockStyle.textNormal
                font.weight: Font.Medium
                color: root.selected ? root.colOnSelected : root.colOnIdle
            }
        }
    }
}
