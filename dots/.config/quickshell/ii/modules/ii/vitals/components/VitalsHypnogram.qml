pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * One night as a stage chart: time from bed to wake across, one lane per stage (awake on
 * top, then REM, light, deep), a rounded bar per stretch in the stage's colour role and a
 * thin step between lanes where the stage changes. `stages` is the Day's
 * [[offsetMin, durMin, stage], …]; null or [] draws the whole session as one "asleep"
 * bar, and stages with no known kind ("asleep") get a lane of their own.
 *
 * Drawn on a Canvas: a Health Connect night can hold well over a hundred one-minute
 * stretches, which would be as many items. The bars grow in from the left once, when the
 * chart is built (`entrance`); new data later repaints in place.
 */
Item {
    id: root

    property var stages: null
    /// The session's bounds in epoch ms.
    property real start: 0
    property real end: 0
    /// Grow in from the left when built; false shows it settled.
    property bool entrance: true
    property bool showLabels: true
    property bool showAxis: true
    property color colLabel: ClockStyle.colOnSurfaceVariant

    implicitHeight: 200

    readonly property real minutes: Math.max(1, (root.end - root.start) / 60000)

    // Neighbouring stretches of one stage read as one bar; a one-minute waking still gets
    // a bar wide enough to see when it is drawn.
    readonly property var blocks: {
        const list = Array.isArray(root.stages) && root.stages.length > 0 ? root.stages : [[0, root.minutes, "asleep"]];
        const out = [];
        for (const s of list) {
            const stage = root.order.includes(s[2]) ? s[2] : "asleep";
            const last = out[out.length - 1];
            if (last && last.stage === stage && Math.abs(last.from + last.len - s[0]) < 1)
                last.len = s[0] + s[1] - last.from;
            else
                out.push({ from: s[0], len: s[1], stage: stage });
        }
        return out;
    }

    readonly property var order: ["awake", "asleep", "rem", "light", "deep"]
    // The four staged lanes whenever any stage is known, so nights compare at a glance;
    // "asleep" gets a lane only when the night has some.
    readonly property var lanes: {
        const seen = {};
        for (const b of root.blocks)
            seen[b.stage] = true;
        const staged = seen.awake || seen.rem || seen.light || seen.deep;
        return root.order.filter(s => s === "asleep" ? seen.asleep === true : staged);
    }
    readonly property var stageNames: ({
        awake: Translation.tr("Awake"),
        asleep: Translation.tr("Asleep"),
        rem: Translation.tr("REM"),
        light: Translation.tr("Light"),
        deep: Translation.tr("Deep")
    })

    readonly property real labelWidth: root.showLabels ? Math.min(64, Math.max(44, root.width * 0.12)) : 0
    readonly property real axisHeight: root.showAxis ? 22 : 0
    readonly property real plotX: root.labelWidth + (root.showLabels ? ClockStyle.gapSmall : 0)
    readonly property real plotWidth: Math.max(1, root.width - root.plotX)
    readonly property real plotHeight: Math.max(1, root.height - root.axisHeight)
    readonly property real laneHeight: root.plotHeight / Math.max(1, root.lanes.length)

    /// Whole hours inside the night, thinned so the labels never touch.
    readonly property var ticks: {
        if (!root.showAxis || root.end <= root.start)
            return [];
        const hourMs = 3600000;
        const hours = (root.end - root.start) / hourMs;
        const fit = Math.max(1, Math.floor(root.plotWidth / 52));
        const step = [1, 2, 3, 4, 6].find(s => hours / s <= fit) ?? 6;
        const first = new Date(root.start);
        first.setMinutes(0, 0, 0);
        const out = [];
        for (let t = first.getTime() + hourMs; t < root.end; t += hourMs) {
            if (new Date(t).getHours() % step === 0)
                out.push({ x: (t - root.start) / (root.end - root.start), label: Qt.formatTime(new Date(t), "HH:mm") });
        }
        return out;
    }

    property real reveal: root.entrance && !ClockStyle.reducedMotion ? 0 : 1
    Component.onCompleted: root.reveal = 1
    Behavior on reveal {
        NumberAnimation {
            duration: ClockStyle.motionEnter.duration * 2
            easing.type: Easing.BezierSpline
            easing.bezierCurve: ClockStyle.motionEnter.bezierCurve
        }
    }

    Repeater {
        model: ScriptModel {
            values: root.showLabels ? root.lanes : []
        }

        StyledText {
            required property var modelData
            required property int index
            x: 0
            y: Math.round(index * root.laneHeight + (root.laneHeight - height) / 2)
            width: root.labelWidth
            text: root.stageNames[modelData] ?? ""
            elide: Text.ElideRight
            font.pixelSize: ClockStyle.textSmall
            font.weight: Font.DemiBold
            color: root.colLabel
        }
    }

    Item {
        x: root.plotX
        width: root.plotWidth * root.reveal
        height: root.plotHeight
        clip: true

        Canvas {
            id: canvas
            width: root.plotWidth
            height: root.plotHeight
            renderStrategy: Canvas.Cooperative

            // The stage colours too, so a new scheme (wallpaper, light/dark) repaints.
            readonly property var paintKey: [root.blocks, root.lanes, width, height, root.minutes, root.colLabel, VitalsStyle.colStage("deep"), VitalsStyle.colStage("light"), VitalsStyle.colStage("rem"), VitalsStyle.colStage("awake")]
            onPaintKeyChanged: requestPaint()

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const lanes = root.lanes, blocks = root.blocks, w = width, lh = root.laneHeight;
                const barH = Math.max(6, Math.min(lh * 0.62, 36));
                const laneY = stage => lanes.indexOf(stage) * lh + lh / 2;
                const px = min => min / root.minutes * w;

                // The steps first, so the bars cover their ends.
                ctx.strokeStyle = ColorUtils.applyAlpha(root.colLabel, 0.35);
                ctx.lineWidth = 1.5;
                ctx.beginPath();
                for (let i = 1; i < blocks.length; i++) {
                    const x = Math.round(px(blocks[i].from)) + 0.5;
                    ctx.moveTo(x, laneY(blocks[i - 1].stage));
                    ctx.lineTo(x, laneY(blocks[i].stage));
                }
                ctx.stroke();

                for (const b of blocks) {
                    const x = px(b.from);
                    const bw = Math.max(5, px(b.from + b.len) - x);
                    const r = Math.min(barH * 0.32, bw / 2);
                    ctx.fillStyle = VitalsStyle.colStage(b.stage);
                    ctx.beginPath();
                    ctx.roundedRect(x, laneY(b.stage) - barH / 2, bw, barH, r, r);
                    ctx.fill();
                }
            }
        }
    }

    Repeater {
        model: ScriptModel {
            values: root.ticks
        }

        StyledText {
            required property var modelData
            x: Math.round(Math.max(root.plotX, Math.min(root.width - width, root.plotX + modelData.x * root.plotWidth - width / 2)))
            y: root.plotHeight + 4
            text: modelData.label
            font.pixelSize: ClockStyle.textSmall
            color: root.colLabel
            opacity: 0.8
        }
    }
}
