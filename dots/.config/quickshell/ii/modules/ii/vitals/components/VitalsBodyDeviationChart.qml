pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Nights against a baseline: each bar hangs from the middle line, up for a warmer night
 * and down for a cooler one, like the Bedtime chart's bars from the target. A night
 * without enough nights before it to have a baseline keeps its column, empty.
 */
Item {
    id: root

    /// Oldest first: [{label, tip, delta}] where delta is null without a baseline.
    property var items: []
    property int selectedIndex: -1
    property color colUp: ClockStyle.colTertiary
    property color colDown: ClockStyle.colPrimary
    /// The pane's content colour, for the middle line, ticks and labels.
    property color colContent: ClockStyle.colOnSurface
    property var formatValue: v => String(v)

    readonly property int count: root.items ? root.items.length : 0
    readonly property var deltas: Array.from(root.items ?? []).map(i => i.delta).filter(d => d !== null && d !== undefined)
    // At least ±0.5 °C, so a quiet fortnight does not fill the chart with noise.
    readonly property real reach: Math.max(0.5, Math.ceil(Math.max(0, ...root.deltas.map(Math.abs)) * 2) / 2)

    readonly property int labelHeight: 18
    readonly property real tickWidth: Math.max(30, tickMetrics.width + 6)
    readonly property real plotWidth: Math.max(0, root.width - root.tickWidth - ClockStyle.gapSmall)
    readonly property real plotHeight: Math.max(0, root.height - root.labelHeight - 6)
    readonly property real middle: root.plotHeight / 2
    readonly property real columnWidth: root.count > 0 ? root.plotWidth / root.count : 0
    readonly property int stride: Math.max(1, Math.ceil(root.count * 40 / Math.max(1, root.plotWidth)))

    implicitHeight: 180

    TextMetrics {
        id: tickMetrics
        font.pixelSize: ClockStyle.textSmall
        font.weight: Font.Medium
        text: root.formatValue(-root.reach)
    }

    Repeater {
        model: [root.reach, 0, -root.reach]

        Item {
            id: gridLine
            required property real modelData
            width: root.width
            height: 1
            y: root.middle - root.middle * gridLine.modelData / root.reach

            Rectangle {
                width: root.plotWidth
                height: gridLine.modelData === 0 ? 2 : 1
                y: gridLine.modelData === 0 ? -0.5 : 0
                color: ColorUtils.applyAlpha(root.colContent, gridLine.modelData === 0 ? 0.3 : 0.1)
            }

            StyledText {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.formatValue(gridLine.modelData)
                font.pixelSize: ClockStyle.textSmall
                font.weight: Font.Medium
                color: root.colContent
                opacity: 0.7
            }
        }
    }

    Repeater {
        model: root.count

        Item {
            id: column
            required property int index
            readonly property var item: root.items[column.index]
            readonly property bool hasDelta: column.item?.delta !== null && column.item?.delta !== undefined
            readonly property bool selected: column.index === root.selectedIndex
            readonly property real barWidth: Math.max(4, Math.min(16, root.columnWidth * 0.6))

            x: column.index * root.columnWidth
            width: root.columnWidth
            height: root.height

            Rectangle {
                visible: column.hasDelta
                readonly property real length: column.hasDelta ? Math.max(4, root.middle * Math.min(1, Math.abs(column.item.delta) / root.reach)) : 0
                x: (column.width - width) / 2
                y: column.hasDelta && column.item.delta >= 0 ? root.middle - length : root.middle
                width: column.barWidth
                height: length
                radius: Math.min(width / 2, height / 2, ClockStyle.radiusSmall)
                color: ColorUtils.applyAlpha(column.hasDelta && column.item.delta >= 0 ? root.colUp : root.colDown,
                    column.selected || mouse.containsMouse ? 1 : 0.75)

                Behavior on color {
                    animation: ClockStyle.motionFast.colorAnimation.createObject(this)
                }
            }

            StyledText {
                visible: column.selected || (root.count - 1 - column.index) % root.stride === 0
                y: root.plotHeight + 6
                x: Math.max(-column.x, Math.min(root.plotWidth - column.x - implicitWidth, (column.width - implicitWidth) / 2))
                text: column.item?.label ?? ""
                font.pixelSize: ClockStyle.textSmall
                font.weight: column.selected ? Font.Bold : Font.Medium
                color: root.colContent
                opacity: column.selected ? 1 : 0.7
            }

            MouseArea {
                id: mouse
                width: parent.width
                height: root.plotHeight
                hoverEnabled: true
            }

            StyledToolTip {
                extraVisibleCondition: mouse.containsMouse
                text: column.item?.tip ?? ""
            }
        }
    }
}
