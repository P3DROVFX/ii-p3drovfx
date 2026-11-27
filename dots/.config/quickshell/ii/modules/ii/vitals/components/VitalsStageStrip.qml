import QtQuick
import qs.modules.common
import qs.modules.ii.clock.components

/**
 * One night as a strip of its sleep stages, bed on the left and wake on the right, each
 * stage in its colour (VitalsStyle.colStage). `stages` is the Day's
 * [[offsetMin, durMin, stage], …]; null or [] draws the night as one "asleep" bar (the
 * stages arrive with the day file). The strip grows in from the left once, when built.
 */
Item {
    id: root

    property var stages: null
    /// The night's length in minutes (end − start), the strip's full width.
    property real minutes: 0

    implicitHeight: VitalsStyle.stageStripHeight

    // Neighbouring entries of the same stage read as one block.
    readonly property var blocks: {
        const total = Math.max(1, root.minutes);
        const list = Array.isArray(root.stages) && root.stages.length > 0 ? root.stages : [[0, total, "asleep"]];
        const out = [];
        for (const s of list) {
            const last = out[out.length - 1];
            if (last && last.stage === s[2] && Math.abs(last.from + last.len - s[0]) < 1)
                last.len += s[1];
            else
                out.push({ from: s[0], len: s[1], stage: s[2] });
        }
        return out.map(b => ({ x: b.from / total, w: b.len / total, stage: b.stage }));
    }

    property real reveal: ClockStyle.reducedMotion ? 1 : 0
    Component.onCompleted: root.reveal = 1
    Behavior on reveal {
        NumberAnimation {
            duration: ClockStyle.motionEnter.duration * 2
            easing.type: Easing.BezierSpline
            easing.bezierCurve: ClockStyle.motionEnter.bezierCurve
        }
    }

    Item {
        width: root.width * root.reveal
        height: root.height
        clip: true

        Repeater {
            model: root.blocks

            Rectangle {
                required property var modelData
                required property int index
                readonly property bool first: index === 0
                readonly property bool last: index === root.blocks.length - 1
                x: Math.round(modelData.x * root.width)
                width: Math.max(1, Math.round((modelData.x + modelData.w) * root.width) - x - (last ? 0 : 1))
                height: root.height
                color: VitalsStyle.colStage(modelData.stage)
                readonly property real capRadius: ClockStyle.pill(root.height)
                topLeftRadius: first ? capRadius : Appearance.rounding.unsharpen
                bottomLeftRadius: first ? capRadius : Appearance.rounding.unsharpen
                topRightRadius: last ? capRadius : Appearance.rounding.unsharpen
                bottomRightRadius: last ? capRadius : Appearance.rounding.unsharpen
            }
        }
    }
}
