pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The period's histogram, drawn in the colour of the pane it sits on: one thick bar per
 * hour or day standing in a faint full-height track, the current bucket in the full
 * content colour and the rest tinted, the way the Limits hero draws its week.
 *
 * Every bucket is a target: a click narrows the page to it and a second click clears
 * that again. A day still in progress keeps its later hours as empty tracks rather than
 * stretching the hours so far across the whole width, so an hour always sits in the
 * same place on the axis.
 */
Item {
    id: root

    /// One value per bucket, full length (24 for a day, one per date otherwise).
    property var values: []
    property var labels: []
    /// Longer names for the tooltip ("2026-09-14" rather than "14").
    property var tooltipLabels: root.labels
    /// The bucket that is now, or -1 in a period that is already over.
    property int nowIndex: -1
    /// Buckets after `nowIndex` have not happened yet: drawn as empty tracks, inert.
    property bool trimFuture: false
    property int focusedIndex: -1
    property int labelStride: 1
    /// Count the stride back from the last bucket (days) rather than from the first.
    property bool labelAnchorEnd: false
    /// Top of the axis for values on a known scale (a battery level); 0 follows the data.
    property real axisCeiling: 0
    /// Ticks land on whole minutes and hours rather than on decimal steps.
    property bool timeScale: false
    /// What one decimal step is worth for non-time values (mJ per Wh, mWh per Wh).
    property real valueUnit: 1
    property var formatValue: value => `${value}`
    property var formatTick: root.formatValue
    /// Emphasis of one bucket between 0 and 1, when the bars mean different things
    /// (charging against draining). Null leaves every past bucket at the same tint.
    property var emphasisAt: null
    /// Extra words for one bucket's tooltip, after its value.
    property var noteAt: null
    property string emptyText: Translation.tr("Nothing recorded yet")

    property color colContent: ClockStyle.colOnPrimary
    property color colPane: ClockStyle.colPrimary

    signal barClicked(int index)

    readonly property int count: root.values ? root.values.length : 0
    readonly property int lastLive: root.trimFuture && root.nowIndex >= 0 ? root.nowIndex : root.count - 1
    readonly property real maxValue: {
        let max = 0;
        for (let i = 0; i <= root.lastLive && i < root.count; i++)
            max = Math.max(max, root.values[i] ?? 0);
        return max;
    }
    readonly property bool hasData: root.maxValue > 0

    function niceStep(target: real): real {
        if (root.timeScale && target <= 86400) {
            const steps = [1, 5, 15, 30, 60, 120, 300, 600, 900, 1800, 3600, 7200, 10800, 21600, 43200, 86400];
            for (const step of steps) {
                if (step >= target)
                    return step;
            }
        }
        const unit = root.timeScale ? 86400 : root.valueUnit;
        const scaled = target / unit;
        const magnitude = Math.pow(10, Math.floor(Math.log10(Math.max(scaled, 1e-9))));
        for (const multiple of [1, 2, 5]) {
            if (magnitude * multiple >= scaled)
                return unit * magnitude * multiple;
        }
        return unit * magnitude * 10;
    }

    readonly property real axisMax: {
        if (root.axisCeiling > 0)
            return root.axisCeiling;
        if (root.maxValue <= 0)
            return 1;
        const step = root.niceStep(root.maxValue / 2);
        const max = Math.ceil(root.maxValue / step) * step;
        return max > 0 ? max : root.maxValue;
    }

    readonly property int labelHeight: 18
    readonly property real tickWidth: Math.max(30, tickMetrics.width + 6)
    readonly property real plotWidth: Math.max(0, root.width - root.tickWidth - ClockStyle.gapSmall)
    readonly property real plotHeight: Math.max(0, root.height - root.labelHeight - 6)
    readonly property real gap: root.count > 16 ? 2 : 4
    readonly property real columnWidth: root.count > 0
        ? Math.max(1, (root.plotWidth - root.gap * (root.count - 1)) / root.count) : 0
    /// Labels never closer than one label's width, whatever stride was asked for.
    readonly property int stride: Math.max(1, root.labelStride, Math.ceil(root.count * 46 / Math.max(1, root.plotWidth)))

    implicitHeight: 160

    TextMetrics {
        id: tickMetrics
        font.pixelSize: ClockStyle.textSmall
        font.weight: Font.Medium
        text: root.formatTick(root.axisMax)
    }

    // ── Grid and ticks ──────────────────────────────────────────────────
    Repeater {
        model: root.hasData ? [1, 0.5] : []

        Item {
            id: gridLine
            required property real modelData
            width: root.width
            height: 1
            y: root.plotHeight - root.plotHeight * gridLine.modelData

            Rectangle {
                width: root.plotWidth
                height: 1
                color: ColorUtils.applyAlpha(root.colContent, 0.16)
            }

            StyledText {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.formatTick(root.axisMax * gridLine.modelData)
                font.pixelSize: ClockStyle.textSmall
                font.weight: Font.Medium
                color: root.colContent
                opacity: 0.7
            }
        }
    }

    // ── Buckets ─────────────────────────────────────────────────────────
    Row {
        spacing: root.gap
        visible: root.hasData

        Repeater {
            model: root.count

            Item {
                id: bucket
                required property int index
                readonly property real value: root.values[bucket.index] ?? 0
                readonly property bool future: root.trimFuture && root.nowIndex >= 0 && bucket.index > root.nowIndex
                readonly property bool isNow: bucket.index === root.nowIndex
                readonly property bool isFocused: bucket.index === root.focusedIndex
                readonly property real radius: Math.min(bucket.width / 2, ClockStyle.radiusSmall)
                readonly property bool showLabel: {
                    if (bucket.isNow)
                        return true;
                    const step = root.labelAnchorEnd ? root.count - 1 - bucket.index : bucket.index;
                    // Keep clear of the "now" label so the two never overlap.
                    if (root.nowIndex >= 0 && Math.abs(bucket.index - root.nowIndex) < root.stride)
                        return false;
                    return step % root.stride === 0;
                }
                readonly property real emphasis: {
                    if (bucket.isFocused)
                        return 1;
                    if (root.focusedIndex >= 0)
                        return 0.28;
                    if (bucket.isNow)
                        return 1;
                    return typeof root.emphasisAt === "function" ? root.emphasisAt(bucket.index) : 0.6;
                }

                width: root.columnWidth
                height: root.height

                Rectangle {
                    id: track
                    width: parent.width
                    height: root.plotHeight
                    radius: bucket.radius
                    color: ColorUtils.applyAlpha(root.colContent,
                        bucket.future ? 0.04 : bucketMouse.containsMouse ? 0.16 : 0.08)

                    Behavior on color {
                        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: bucket.value > 0
                            ? Math.max(bucket.radius * 2, track.height * Math.min(1, bucket.value / root.axisMax)) : 0
                        radius: bucket.radius
                        color: ColorUtils.applyAlpha(root.colContent,
                            Math.min(1, bucket.emphasis + (bucketMouse.containsMouse ? 0.2 : 0)))

                        Behavior on height {
                            enabled: !ClockStyle.reducedMotion
                            animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                        }
                        Behavior on color {
                            animation: ClockStyle.motionFast.colorAnimation.createObject(this)
                        }
                    }
                }

                StyledText {
                    visible: bucket.showLabel
                    y: root.plotHeight + 6
                    // Centred under the bucket, but held inside the plot at either end.
                    x: Math.max(-bucket.x,
                        Math.min(root.plotWidth - bucket.x - implicitWidth, (bucket.width - implicitWidth) / 2))
                    text: bucket.isNow && bucket.index === root.count - 1 && !root.trimFuture
                        ? Translation.tr("now") : (root.labels[bucket.index] ?? "")
                    font.pixelSize: ClockStyle.textSmall
                    font.weight: bucket.isNow || bucket.isFocused ? Font.Bold : Font.Medium
                    color: root.colContent
                    opacity: bucket.isNow || bucket.isFocused ? 1 : 0.7
                }

                MouseArea {
                    id: bucketMouse
                    width: parent.width
                    height: root.plotHeight
                    enabled: !bucket.future
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.barClicked(bucket.index)
                }

                StyledToolTip {
                    extraVisibleCondition: bucketMouse.containsMouse && bucket.value > 0
                    text: {
                        const label = root.tooltipLabels[bucket.index] ?? "";
                        const note = typeof root.noteAt === "function" ? root.noteAt(bucket.index) : "";
                        return `${label} · ${root.formatValue(bucket.value)}` + (note.length > 0 ? ` · ${note}` : "");
                    }
                }
            }
        }
    }

    // ── Empty ───────────────────────────────────────────────────────────
    Column {
        anchors.centerIn: parent
        visible: !root.hasData
        spacing: ClockStyle.gapSmall

        MaterialShapeWrappedMaterialSymbol {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "bar_chart_off"
            iconSize: 28
            padding: 12
            shape: MaterialShape.Shape.Ghostish
            color: ColorUtils.applyAlpha(root.colContent, 0.14)
            colSymbol: root.colContent
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.emptyText
            font.pixelSize: ClockStyle.textNormal
            font.weight: Font.DemiBold
            color: root.colContent
            opacity: 0.85
        }
    }
}
