import QtQuick
import "ShapeMorphCache.js" as ShapeMorphCache

/**
 * ShapeCanvas with shared morph geometry.
 *
 * Same properties and painting as `shapes/ShapeCanvas.qml`, which is a git
 * submodule (end-4/rounded-polygon-qmljs) and cannot carry local changes.
 * Two costs are gone:
 *  - the Morph between two polygons comes from ShapeMorphCache instead of
 *    being rebuilt (twice) by every canvas;
 *  - a canvas that is created with its shape no longer "morphs" from that
 *    shape to itself. The change handler fires at creation, so every badge
 *    on a freshly opened page used to repaint in JS for 350 ms to draw a
 *    picture that never changed.
 */
Canvas {
    id: root
    property color color: "#685496"
    property var roundedPolygon: null
    property bool polygonIsNormalized: true
    property real borderWidth: 0
    property color borderColor: color
    property bool debug: false
    property real xOffset: 0
    property real yOffset: 0

    // Internals: size
    property var bounds: root.roundedPolygon ? root.roundedPolygon.calculateBounds() : [0, 0, 0, 0]
    implicitWidth: bounds[2] - bounds[0]
    implicitHeight: bounds[3] - bounds[1]

    // Internals: anim
    property var prevRoundedPolygon: null
    property double progress: 1
    property var morphEntry: null
    readonly property var morph: root.morphEntry ? root.morphEntry.morph : null
    property Animation animation: NumberAnimation {
        duration: 350
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.42, 1.67, 0.21, 0.90, 1, 1] // Material 3 Expressive fast spatial (https://m3.material.io/styles/motion/overview/specs)
    }

    onRoundedPolygonChanged: {
        const from = root.prevRoundedPolygon ?? root.roundedPolygon;
        root.morphEntry = ShapeMorphCache.entry(from, root.roundedPolygon);
        morphBehavior.enabled = false;
        if (from === root.roundedPolygon) {
            root.progress = 1;
            morphBehavior.enabled = true;
            root.requestPaint();
        } else {
            root.progress = 0;
            morphBehavior.enabled = true;
            root.progress = 1;
        }
        root.prevRoundedPolygon = root.roundedPolygon;
    }

    Behavior on progress {
        id: morphBehavior
        animation: root.animation
    }

    /**
     * A Canvas repaints itself after a resize only while it is visible, and showing it
     * later repaints nothing. A shape that got its size while its panel was closed -
     * or settled on a new one, as a quick toggle does when its tile is laid out -
     * therefore stayed blank until something else happened to repaint it: which tile
     * lost its coloured circle depended on what was resized while out of sight.
     * (A paint asked for while hidden is dropped as well when nothing was ever
     * painted, so the repaint waits for the moment it is shown.)
     */
    property bool paintMissed: false
    onWidthChanged: if (!visible) paintMissed = true
    onHeightChanged: if (!visible) paintMissed = true
    onVisibleChanged: {
        if (!visible || !paintMissed)
            return;
        paintMissed = false;
        requestPaint();
    }

    onProgressChanged: requestPaint()
    onColorChanged: requestPaint()
    onBorderWidthChanged: requestPaint()
    onBorderColorChanged: requestPaint()
    onDebugChanged: requestPaint()
    onXOffsetChanged: requestPaint()
    onYOffsetChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d");
        ctx.fillStyle = root.color;
        ctx.clearRect(0, 0, width, height);
        if (!root.morph)
            return;
        const cubics = root.progress === 1
            ? ShapeMorphCache.settledCubics(root.morphEntry)
            : root.morph.asCubics(root.progress);
        if (cubics.length === 0)
            return;
        const size = Math.min(root.width, root.height);

        ctx.save();
        if (root.polygonIsNormalized) {
            ctx.scale(size, size);
        }
        ctx.translate(root.xOffset, root.yOffset);

        ctx.beginPath();
        ctx.moveTo(cubics[0].anchor0X, cubics[0].anchor0Y);
        for (const cubic of cubics) {
            ctx.bezierCurveTo(cubic.control0X, cubic.control0Y, cubic.control1X, cubic.control1Y, cubic.anchor1X, cubic.anchor1Y);
        }
        ctx.closePath();
        ctx.fill();

        if (root.borderWidth > 0) {
            ctx.strokeStyle = root.borderColor;
            ctx.lineWidth = root.borderWidth;
            ctx.stroke();
        }

        if (root.debug) {
            const points = [];
            for (let i = 0; i < cubics.length; ++i) {
                const c = cubics[i];
                if (i === 0)
                    points.push({
                        x: c.anchor0X,
                        y: c.anchor0Y
                    });
                points.push({
                    x: c.anchor1X,
                    y: c.anchor1Y
                });
            }

            let radius = 2;

            ctx.fillStyle = "red";
            for (const p of points) {
                ctx.beginPath();
                ctx.arc(p.x, p.y, radius, 0, Math.PI * 2);
                ctx.fill();
            }
        }

        ctx.restore();
    }
}
