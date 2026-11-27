pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Measurements on a calendar axis: each one a point where it was taken, joined by a line,
 * so months without a weigh-in read as distance rather than being squeezed out. A point is
 * a target that opens that measurement.
 */
Item {
    id: root

    /// Oldest first: [{date: "yyyy-MM-dd", value}].
    property var points: []
    property int selectedIndex: -1
    property color colLine: ClockStyle.colPrimary
    /// The pane's content colour, for ticks and labels.
    property color colContent: ClockStyle.colOnSurface
    property var formatValue: v => String(v)
    property var formatTip: (point, index) => root.formatValue(point.value)
    property real now: Date.now()

    signal pointClicked(int index)

    readonly property int count: root.points ? root.points.length : 0
    readonly property bool hasData: root.count > 0
    readonly property string firstDate: root.hasData ? root.points[0].date : ""
    readonly property string lastDate: root.hasData ? root.points[root.count - 1].date : ""
    readonly property real span: root.hasData ? Math.max(1, VitalsFormat.daysBetween(root.firstDate, root.lastDate)) : 1
    readonly property real lo: {
        if (!root.hasData)
            return 0;
        const vals = Array.from(root.points).map(p => p.value);
        const min = Math.min(...vals), max = Math.max(...vals);
        return min - Math.max(0.5, (max - min) * 0.15);
    }
    readonly property real hi: {
        if (!root.hasData)
            return 1;
        const vals = Array.from(root.points).map(p => p.value);
        const min = Math.min(...vals), max = Math.max(...vals);
        return max + Math.max(0.5, (max - min) * 0.15);
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
    readonly property int dot: 10
    readonly property real tickWidth: Math.max(30, tickMetrics.width + 6)
    readonly property real plotWidth: Math.max(0, root.width - root.tickWidth - ClockStyle.gapSmall)
    readonly property real plotHeight: Math.max(0, root.height - root.labelHeight - 6)

    function xOf(date: string): real {
        if (root.count === 1)
            return root.plotWidth / 2;
        return root.dot / 2 + (root.plotWidth - root.dot) * VitalsFormat.daysBetween(root.firstDate, date) / root.span;
    }

    function yOf(v: real): real {
        return root.dot / 2 + (root.plotHeight - root.dot) * (1 - (v - root.lo) / Math.max(1e-6, root.hi - root.lo));
    }

    implicitHeight: 200

    TextMetrics {
        id: tickMetrics
        font.pixelSize: ClockStyle.textSmall
        font.weight: Font.Medium
        text: root.formatValue(root.ticks[root.ticks.length - 1] ?? root.hi)
    }

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

    Canvas {
        id: canvas
        width: root.plotWidth
        height: root.plotHeight
        visible: root.count > 1
        renderStrategy: Canvas.Cooperative

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        Connections {
            target: root
            function onPointsChanged() {
                canvas.requestPaint();
            }
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.strokeStyle = ColorUtils.applyAlpha(root.colLine, 0.6);
            ctx.lineWidth = 2;
            ctx.lineJoin = "round";
            ctx.beginPath();
            for (let i = 0; i < root.count; i++) {
                const p = root.points[i];
                if (i === 0)
                    ctx.moveTo(root.xOf(p.date), root.yOf(p.value));
                else
                    ctx.lineTo(root.xOf(p.date), root.yOf(p.value));
            }
            ctx.stroke();
        }
    }

    Repeater {
        model: root.count

        Item {
            id: point
            required property int index
            readonly property var data_: root.points[point.index]
            readonly property bool selected: point.index === root.selectedIndex

            x: root.xOf(point.data_.date) - width / 2
            y: root.yOf(point.data_.value) - height / 2
            width: 24
            height: 24

            Rectangle {
                anchors.centerIn: parent
                property real size: point.selected ? root.dot + 4 : mouse.containsMouse ? root.dot + 2 : root.dot
                width: size
                height: size
                radius: size / 2
                color: root.colLine

                Behavior on size {
                    enabled: !ClockStyle.reducedMotion
                    animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                }
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.pointClicked(point.index)
            }

            StyledToolTip {
                extraVisibleCondition: mouse.containsMouse
                text: VitalsFormat.dayLabel(point.data_.date, root.now) + " · " + root.formatTip(point.data_, point.index)
            }
        }
    }

    // First and last day under the axis; the middle only when there is room between them.
    Repeater {
        model: !root.hasData ? [] : root.count === 1 ? [root.firstDate]
            : root.plotWidth > 360 && root.span >= 4 ? [root.firstDate, VitalsFormat.addDays(root.firstDate, Math.round(root.span / 2)), root.lastDate]
            : [root.firstDate, root.lastDate]

        StyledText {
            id: dateLabel
            required property string modelData
            y: root.plotHeight + 6
            x: Math.max(0, Math.min(root.plotWidth - implicitWidth, root.xOf(dateLabel.modelData) - implicitWidth / 2))
            text: VitalsFormat.dayLabel(dateLabel.modelData, root.now)
            font.pixelSize: ClockStyle.textSmall
            font.weight: Font.Medium
            color: root.colContent
            opacity: 0.7
        }
    }
}
