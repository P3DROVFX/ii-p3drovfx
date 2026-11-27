pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * One day of heart rate across midnight to midnight: the mean as a line inside a soft band
 * from each slot's lowest to highest reading, so a run and a calm hour differ in width as
 * well as height. Gaps stay gaps. The axis is the whole day even while it is still going,
 * so an hour always sits in the same place; hovering names an hour and a click opens it.
 */
Item {
    id: root

    /// Equal slots over the day, oldest first: {min, avg, max}, or null where there is none.
    property var slots: []
    property int selectedHour: -1
    property color colLine: ClockStyle.colPrimary
    /// The pane's content colour, for ticks, labels and the hour highlight.
    property color colContent: ClockStyle.colOnSurface
    property var formatValue: v => String(Math.round(v))
    property string emptyText: Translation.tr("No heart rate this day")

    signal hourClicked(int hour)

    readonly property int count: root.slots ? root.slots.length : 0
    readonly property var known: Array.from(root.slots ?? []).filter(s => s !== null && s !== undefined)
    readonly property bool hasData: root.known.length > 0
    // Ticks on round tens: a heart-rate axis is read in tens.
    readonly property real lo: root.hasData ? Math.floor((Math.min(...root.known.map(s => s.min)) - 2) / 10) * 10 : 40
    readonly property real hi: root.hasData ? Math.ceil((Math.max(...root.known.map(s => s.max)) + 2) / 10) * 10 : 160
    readonly property int hoveredHour: mouse.containsMouse ? Math.max(0, Math.min(23, Math.floor(mouse.mouseX / Math.max(1, root.plotWidth) * 24))) : -1

    readonly property int labelHeight: 18
    readonly property real tickWidth: Math.max(30, tickMetrics.width + 6)
    readonly property real plotWidth: Math.max(0, root.width - root.tickWidth - ClockStyle.gapSmall)
    readonly property real plotHeight: Math.max(0, root.height - root.labelHeight - 6)
    readonly property real hourWidth: root.plotWidth / 24

    function yOf(v: real): real {
        return root.plotHeight * (1 - (v - root.lo) / Math.max(1e-6, root.hi - root.lo));
    }

    /// {min, avg, max} over one hour's slots, or null.
    function hourRange(hour: int): var {
        const per = root.count / 24;
        let min = Infinity, max = -Infinity, sum = 0, n = 0;
        for (let i = Math.round(hour * per); i < Math.round((hour + 1) * per); i++) {
            const s = root.slots[i];
            if (!s)
                continue;
            min = Math.min(min, s.min);
            max = Math.max(max, s.max);
            sum += s.avg;
            n++;
        }
        return n > 0 ? { min: min, avg: sum / n, max: max } : null;
    }

    implicitHeight: 220

    TextMetrics {
        id: tickMetrics
        font.pixelSize: ClockStyle.textSmall
        font.weight: Font.Medium
        text: root.formatValue(root.hi)
    }

    // ── Hour highlight (under the plot) ─────────────────────────────────
    Rectangle {
        readonly property int hour: root.hoveredHour >= 0 ? root.hoveredHour : root.selectedHour
        visible: hour >= 0 && root.hasData
        x: hour * root.hourWidth
        width: root.hourWidth
        height: root.plotHeight
        radius: Math.min(width / 2, ClockStyle.radiusSmall)
        color: ColorUtils.applyAlpha(root.colContent, root.hoveredHour >= 0 && root.hoveredHour !== root.selectedHour ? 0.08 : 0.14)
    }

    // ── Grid and ticks ──────────────────────────────────────────────────
    Repeater {
        model: root.hasData ? [root.hi, (root.hi + root.lo) / 2, root.lo] : []

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

    // ── Band and line ───────────────────────────────────────────────────
    Canvas {
        id: canvas
        width: root.plotWidth
        height: root.plotHeight
        visible: root.hasData
        renderStrategy: Canvas.Cooperative

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        Connections {
            target: root
            function onSlotsChanged() {
                canvas.requestPaint();
            }
            function onColLineChanged() {
                canvas.requestPaint();
            }
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const n = root.count;
            if (n === 0)
                return;
            const step = width / n;
            const xOf = i => i * step + step / 2;
            // Runs of consecutive slots, each drawn as its own band and line.
            const runs = [];
            let run = [];
            for (let i = 0; i < n; i++) {
                if (root.slots[i]) {
                    run.push(i);
                } else if (run.length > 0) {
                    runs.push(run);
                    run = [];
                }
            }
            if (run.length > 0)
                runs.push(run);

            ctx.fillStyle = ColorUtils.applyAlpha(root.colLine, 0.24);
            for (const r of runs) {
                ctx.beginPath();
                const pad = r.length === 1 ? step * 0.4 : 0;
                r.forEach((i, k) => {
                    const x = xOf(i) - (k === 0 ? pad : 0);
                    if (k === 0)
                        ctx.moveTo(x, root.yOf(root.slots[i].max));
                    else
                        ctx.lineTo(x, root.yOf(root.slots[i].max));
                });
                if (pad > 0)
                    ctx.lineTo(xOf(r[0]) + pad, root.yOf(root.slots[r[0]].max));
                for (let k = r.length - 1; k >= 0; k--)
                    ctx.lineTo(xOf(r[k]) + (k === r.length - 1 ? pad : 0), root.yOf(root.slots[r[k]].min));
                if (pad > 0)
                    ctx.lineTo(xOf(r[0]) - pad, root.yOf(root.slots[r[0]].min));
                ctx.closePath();
                ctx.fill();
            }

            ctx.strokeStyle = root.colLine;
            ctx.lineWidth = 2;
            ctx.lineJoin = "round";
            ctx.lineCap = "round";
            for (const r of runs) {
                ctx.beginPath();
                r.forEach((i, k) => {
                    if (k === 0)
                        ctx.moveTo(xOf(i), root.yOf(root.slots[i].avg));
                    else
                        ctx.lineTo(xOf(i), root.yOf(root.slots[i].avg));
                });
                if (r.length === 1)
                    ctx.lineTo(xOf(r[0]) + 0.5, root.yOf(root.slots[r[0]].avg));
                ctx.stroke();
            }
        }
    }

    // ── Hours ───────────────────────────────────────────────────────────
    Repeater {
        model: root.hasData ? [0, 6, 12, 18, 24] : []

        StyledText {
            id: hourLabel
            required property int modelData
            y: root.plotHeight + 6
            x: Math.max(0, Math.min(root.plotWidth - implicitWidth, hourLabel.modelData * root.hourWidth - implicitWidth / 2))
            text: String(hourLabel.modelData % 24).padStart(2, "0") + ":00"
            font.pixelSize: ClockStyle.textSmall
            font.weight: Font.Medium
            color: root.colContent
            opacity: 0.7
        }
    }

    MouseArea {
        id: mouse
        width: root.plotWidth
        height: root.plotHeight
        enabled: root.hasData
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (root.hourRange(root.hoveredHour) !== null)
                root.hourClicked(root.hoveredHour);
        }
    }

    StyledToolTip {
        readonly property var range: root.hoveredHour >= 0 ? root.hourRange(root.hoveredHour) : null
        extraVisibleCondition: mouse.containsMouse
        text: {
            const h = root.hoveredHour;
            const span = String(h).padStart(2, "0") + ":00–" + String((h + 1) % 24).padStart(2, "0") + ":00";
            return range
                ? Translation.tr("%1 · %2–%3 · avg %4").arg(span).arg(root.formatValue(range.min)).arg(root.formatValue(range.max)).arg(root.formatValue(range.avg))
                : Translation.tr("%1 · no readings").arg(span);
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
