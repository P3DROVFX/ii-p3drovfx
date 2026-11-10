pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * Screen ruler annotation: the OSD Tuner's ruler design laid along the A→B
 * segment — graduation sticks around a centre line (the measured segment),
 * with the measured size in a primary chip above the rail, centred mid-path.
 * Sticks keep the Tuner's shape language (2 px rounded, 2:1 major/minor) with
 * taller marks and stronger colours so the ruler reads on any screenshot.
 *
 * Geometry is { x1, y1, x2, y2 } in editor-local px; the chip reads capture
 * px (logical × captureScale), the same unit as the editor's size readout.
 * Styling is fixed like the blur tools — no stroke/width restyle.
 */
Item {
    id: root

    property var annData: null
    property real captureScale: 1

    // Graduation marks: 2:1 major/minor height, as in the Tuner's ruler.
    readonly property int majorStickH: 24
    readonly property int minorStickH: 12
    readonly property int stickWidth: 2
    readonly property int spineH: 4

    readonly property var g: annData ? (annData.geom ?? annData) : null
    readonly property real x1: g?.x1 ?? 0
    readonly property real y1: g?.y1 ?? 0
    readonly property real x2: g?.x2 ?? 0
    readonly property real y2: g?.y2 ?? 0
    readonly property real segLen: Math.sqrt(Math.pow(root.x2 - root.x1, 2) + Math.pow(root.y2 - root.y1, 2))
    readonly property int pxLen: Math.round(root.segLen * root.captureScale)
    // The ruler is symmetric, so its frame is normalised to point right-ish
    // (|a| ≤ 90°): the chip stays on the screen-up side at every angle.
    readonly property real angleDeg: {
        const a = Math.atan2(root.y2 - root.y1, root.x2 - root.x1) * 180 / Math.PI;
        return (a > 90 || a <= -90) ? a - 180 * Math.sign(a) : a;
    }
    // Graduation marks in capture px from A: a stick every 10 px, a major one
    // every 50. Below 5 logical px of pitch the minors would merge into a
    // hatch, so they drop to the major spacing. Both ends are major. `t` is
    // the mark's offset from the segment MIDPOINT (the rail frame) — the
    // sticks are placed at `t` directly, never shifted again.
    readonly property var ticks: {
        const sc = Math.max(0.001, root.captureScale);
        const span = root.segLen * sc;
        const minorPx = 10 / sc < 5 ? 50 : 10;
        const out = [];
        const n = Math.floor(span / minorPx);
        for (let k = 0; k <= n; k++) {
            const m = k * minorPx;
            out.push({
                "t": m / sc - root.segLen / 2,
                "major": m % 50 === 0
            });
        }
        if (span - n * minorPx > 0.001)
            out.push({
                "t": root.segLen / 2,
                "major": true
            });
        if (out.length > 0) {
            out[0].major = true;
            out[out.length - 1].major = true;
        }
        return out;
    }

    x: Math.min(root.x1, root.x2) - 24
    y: Math.min(root.y1, root.y2) - 24
    width: Math.abs(root.x2 - root.x1) + 48
    height: Math.abs(root.y2 - root.y1) + 48
    visible: annData !== null

    // Ruler frame: origin at the segment's midpoint, x along the segment.
    Item {
        id: rail

        width: 0
        height: 0
        x: root.width / 2
        y: root.height / 2
        rotation: root.angleDeg

        Repeater {
            model: root.ticks

            Rectangle {
                required property var modelData

                readonly property real stickH: modelData.major ? root.majorStickH : root.minorStickH

                x: modelData.t - root.stickWidth / 2
                y: -stickH / 2
                width: root.stickWidth
                height: stickH
                radius: root.stickWidth / 2
                color: modelData.major ? Appearance.colors.colPrimary : Appearance.colors.colOutline
            }
        }

        // The measured segment, in the middle of the graduation band.
        Rectangle {
            x: -root.segLen / 2
            y: -root.spineH / 2
            width: root.segLen
            height: root.spineH
            radius: root.spineH / 2
            color: Appearance.colors.colPrimary
        }

        // The size chip, above the rail and centred mid-path.
        Rectangle {
            id: chip

            readonly property int padH: 14
            readonly property int padV: 7

            width: chipLabel.implicitWidth + chip.padH * 2
            height: chipLabel.implicitHeight + chip.padV * 2
            x: -chip.width / 2
            y: -(root.majorStickH / 2 + 10 + chip.height)
            radius: Math.min(chip.height / 2, Appearance.rounding.large)
            color: Appearance.colors.colPrimary

            StyledText {
                id: chipLabel

                anchors.centerIn: parent
                text: root.pxLen + " px"
                color: Appearance.colors.colOnPrimary
                font.pixelSize: 24
                font.weight: Font.Bold
            }
        }
    }
}
