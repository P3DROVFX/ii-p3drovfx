import QtQuick

/**
 * Offsets that dilate a shape when it is redrawn once at each of them.
 *
 * This is the primitive behind every die-cut in the bar: render the thing you
 * want to subtract at all of these offsets, in black, into a mask, then feed it
 * to an inverted `OpacityMask`. The union of the copies is the original shape
 * grown by `radius`, which is the margin that ends up burned around it.
 *
 * A ring rather than a filled disc is enough as long as neighbouring samples
 * land under a pixel apart — 16 of them do at any radius a bar widget uses
 * (2 * radius * sin(pi/16) ≈ 0.39 * radius).
 */
QtObject {
    id: root

    property real radius: 2
    property int steps: 16

    readonly property var samples: {
        const out = [
            {
                dx: 0,
                dy: 0
            }
        ];
        for (let i = 0; i < root.steps; i++) {
            const angle = i / root.steps * Math.PI * 2;
            out.push({
                dx: Math.cos(angle) * root.radius,
                dy: Math.sin(angle) * root.radius
            });
        }
        return out;
    }
}
