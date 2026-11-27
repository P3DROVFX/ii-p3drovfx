pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * One floating bar per day from its lowest to its highest reading, with the day's mean as
 * a notch cut into the bar: how wide a day ranged reads at a glance, and the notch keeps
 * the typical value from hiding in it. A day without readings is an empty column, not a
 * zero. Clicking a bar picks that day.
 */
Item {
    id: root

    /// One per column, oldest first: {min, avg, max}, or null for a day without readings.
    property var ranges: []
    property var labels: []
    /// Longer names for the tooltip ("Tuesday" rather than "Tue").
    property var tooltipLabels: root.labels
    property int selectedIndex: -1
    property color colBar: ClockStyle.colPrimary
    /// The pane's content colour, for ticks and labels.
    property color colContent: ClockStyle.colOnSurface
    /// The pane's own colour: the mean is cut out of the bar in it.
    property color colPane: VitalsStyle.colTile
    property var formatValue: v => String(Math.round(v))
    property string emptyText: Translation.tr("No readings")

    signal barClicked(int index)

    readonly property int count: root.ranges ? root.ranges.length : 0
    readonly property var known: Array.from(root.ranges ?? []).filter(r => r !== null && r !== undefined)
    readonly property bool hasData: root.known.length > 0
    // Some room above and below so the extremes do not sit on the frame.
    readonly property real lo: {
        if (!root.hasData)
            return 0;
        const min = Math.min(...root.known.map(r => r.min)), max = Math.max(...root.known.map(r => r.max));
        return Math.floor(min - Math.max(1, (max - min) * 0.08));
    }
    readonly property real hi: {
        if (!root.hasData)
            return 1;
        const min = Math.min(...root.known.map(r => r.min)), max = Math.max(...root.known.map(r => r.max));
        return Math.ceil(max + Math.max(1, (max - min) * 0.08));
    }

    /// Grid values on a round step (1, 2, 2.5 or 5 × 10ⁿ) inside the plotted range.
    readonly property var ticks: {
        if (!root.hasData)
            return [];
        const raw = (root.hi - root.lo) / 4;
        const mag = Math.pow(10, Math.floor(Math.log10(raw)));
        const step = [1, 2, 2.5, 5, 10].map(m => m * mag).find(s => s >= raw);
        const out = [];
        for (let v = Math.ceil(root.lo / step) * step; v <= root.hi; v += step)
            out.push(Math.round(v / step) * step);
        return out;
    }

    readonly property int labelHeight: 18
    readonly property real tickWidth: Math.max(30, tickMetrics.width + 6)
    readonly property real plotWidth: Math.max(0, root.width - root.tickWidth - ClockStyle.gapSmall)
    readonly property real plotHeight: Math.max(0, root.height - root.labelHeight - 6)
    readonly property real columnWidth: root.count > 0 ? root.plotWidth / root.count : 0
    readonly property real barWidth: Math.max(4, Math.min(14, root.columnWidth * 0.5))
    readonly property int stride: Math.max(1, Math.ceil(root.count * 40 / Math.max(1, root.plotWidth)))

    function yOf(v: real): real {
        return root.plotHeight * (1 - (v - root.lo) / Math.max(1e-6, root.hi - root.lo));
    }

    implicitHeight: 160

    TextMetrics {
        id: tickMetrics
        font.pixelSize: ClockStyle.textSmall
        font.weight: Font.Medium
        text: root.formatValue(root.ticks[root.ticks.length - 1] ?? root.hi)
    }

    // ── Grid and ticks ──────────────────────────────────────────────────
    Repeater {
        model: root.ticks

        Item {
            id: gridLine
            required property real modelData
            width: root.width
            height: 1
            y: root.yOf(gridLine.modelData)

            Rectangle {
                width: root.plotWidth
                height: 1
                color: ColorUtils.applyAlpha(root.colContent, 0.1)
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

    // ── Days ────────────────────────────────────────────────────────────
    Repeater {
        model: root.hasData ? root.count : 0

        Item {
            id: column
            required property int index
            readonly property var range: root.ranges[column.index] ?? null
            readonly property bool selected: column.index === root.selectedIndex
            readonly property bool showLabel: column.selected
                || ((root.count - 1 - column.index) % root.stride === 0
                    && (root.selectedIndex < 0 || Math.abs(column.index - root.selectedIndex) >= root.stride))

            x: column.index * root.columnWidth
            width: root.columnWidth
            height: root.height

            Rectangle {
                id: bar
                visible: column.range !== null
                x: (column.width - width) / 2
                y: column.range ? root.yOf(column.range.max) : 0
                width: root.barWidth
                height: column.range ? Math.max(root.barWidth, root.yOf(column.range.min) - root.yOf(column.range.max)) : 0
                radius: width / 2
                color: ColorUtils.applyAlpha(root.colBar, column.selected ? 1 : mouse.containsMouse ? 0.8 : root.selectedIndex >= 0 ? 0.4 : 0.6)

                Behavior on y {
                    enabled: !ClockStyle.reducedMotion
                    animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                }
                Behavior on height {
                    enabled: !ClockStyle.reducedMotion
                    animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                }
                Behavior on color {
                    animation: ClockStyle.motionFast.colorAnimation.createObject(this)
                }

                Rectangle {
                    readonly property real size: Math.max(3, root.barWidth - 6)
                    x: (bar.width - size) / 2
                    y: column.range ? Math.max(0, Math.min(bar.height - size, root.yOf(column.range.avg) - bar.y - size / 2)) : 0
                    width: size
                    height: size
                    radius: size / 2
                    color: root.colPane
                }
            }

            StyledText {
                visible: column.showLabel
                y: root.plotHeight + 6
                x: Math.max(-column.x, Math.min(root.plotWidth - column.x - implicitWidth, (column.width - implicitWidth) / 2))
                text: root.labels[column.index] ?? ""
                font.pixelSize: ClockStyle.textSmall
                font.weight: column.selected ? Font.Bold : Font.Medium
                color: root.colContent
                opacity: column.selected ? 1 : 0.7
            }

            MouseArea {
                id: mouse
                width: parent.width
                height: root.plotHeight
                enabled: column.range !== null
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.barClicked(column.index)
            }

            StyledToolTip {
                extraVisibleCondition: mouse.containsMouse && column.range !== null
                text: column.range
                    ? Translation.tr("%1 · %2–%3 · avg %4").arg(root.tooltipLabels[column.index] ?? "")
                        .arg(root.formatValue(column.range.min)).arg(root.formatValue(column.range.max)).arg(root.formatValue(column.range.avg))
                    : ""
            }
        }
    }

    StyledText {
        anchors.centerIn: parent
        visible: !root.hasData
        text: root.emptyText
        font.pixelSize: ClockStyle.textNormal
        color: root.colContent
        opacity: 0.7
    }
}
