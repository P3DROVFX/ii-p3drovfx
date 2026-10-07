pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

import qs.modules.common
import "StrokeGeometry.js" as StrokeGeometry

/**
 * The ink itself: committed strokes, plus the one currently under the pen.
 *
 * Two renderers, each doing only what it is cheap at.
 *
 * The finished strokes live on a canvas, and the canvas is painted *incrementally*: a
 * stroke that was just added is drawn on top of what is already there, and only an undo,
 * an erase or a new sheet clears and repaints the lot. Repainting every stroke whenever
 * one was added made each new stroke cost as much as the whole drawing.
 *
 * The stroke under the pen is a vector `Shape`, not a second canvas. A canvas is a
 * screen-sized image: every sample used to clear it, repaint the whole stroke into it
 * and upload all of its pixels to the GPU again — megabytes per pointer event, for a
 * line a few pixels wide. The shape is a handful of vertices that the GPU strokes and
 * antialiases itself, and it is rebuilt at most once per frame however fast the device
 * reports.
 *
 * Both draw the same flattened geometry (StrokeGeometry.flattened), so a stroke does not
 * move when it is handed from one to the other.
 */
Item {
    id: root

    /// [{ points: [{x,y,p}], color, width, usePressure }]
    property var strokes: []
    /// The stroke being drawn right now, or null. Its `points` array may grow in place;
    /// call `refreshLive()` after appending to it.
    property var liveStroke: null

    /// Paint in the GUI thread and into an image rather than an FBO. Only the offscreen
    /// crop needs this: it is the render target `Canvas.save` can read back from, and it
    /// is worth nothing on the visible sheet, where threaded painting is what keeps a
    /// stroke ahead of the pen.
    property bool immediate: false

    /// The finished strokes have been painted. What a save waits for — a Canvas paints
    /// when the scene graph gets to it, so writing straight after requesting a repaint
    /// wrote a blank file.
    signal committedPainted()

    /// Emitted once a `saveCommitted` has finished, with whether the file was written.
    signal saved(bool ok, string path)

    /**
     * Writes the finished strokes to `path` as a PNG. Asynchronous; watch `saved`.
     *
     * Grabbed rather than saved through `Canvas.save`, which cannot work here: that
     * function resolves its filename against the component's base URL, and under
     * Quickshell every component's base URL is a `qs:` URL rather than a file one. The
     * resolution produces something with no local file at all, so the call fails with
     * "No file name specified" for an argument that was a perfectly good absolute path.
     * A grab result takes the URL as given.
     */
    function saveCommitted(path) {
        const target = String(path ?? "");
        const grabbed = committed.grabToImage(result => {
            root.saved(result.saveToFile(`file://${target}`), target);
        });
        if (!grabbed)
            root.saved(false, target);
    }

    // ── What the committed canvas still has to paint ────────────────────────
    /// The list the canvas last painted, and whether the next paint must start over.
    property var _painted: []
    property bool _repaintAll: true

    onStrokesChanged: {
        const next = root.strokes ?? [];
        const previous = root._painted;
        // Appended to, with everything before untouched: paint just the new strokes.
        // Anything else — an undo, an erase, another sheet — starts over.
        let appended = !root._repaintAll && next.length >= previous.length;
        for (let i = 0; appended && i < previous.length; ++i)
            appended = next[i] === previous[i];
        if (!appended)
            root._repaintAll = true;
        // A stroke just handed over from the pen: the shape keeps showing it until the
        // canvas has painted it, or the line would blink out for a frame in between.
        if (root.liveStroke)
            root._awaitingCommit = true;
        committed.requestPaint();
    }
    onWidthChanged: root.refresh()
    onHeightChanged: root.refresh()

    function refresh() {
        root._repaintAll = true;
        committed.requestPaint();
        root.refreshLive();
    }

    /// The live stroke changed. Rebuilt at most once per ~8 ms, however many samples
    /// arrived in between — a 1000 Hz mouse would otherwise rebuild it a thousand times
    /// a second for a screen that shows sixty or a hundred and forty-four of them.
    ///
    /// A plain timer, not a FrameAnimation: starting and stopping an animation on every
    /// pointer event woke the scene's animation driver each time, and in a shell with
    /// dozens of windows that alone cost most of a CPU core while drawing.
    property bool _liveDirty: false
    property bool _awaitingCommit: false
    property bool _liveShown: false

    function refreshLive() {
        root._liveDirty = true;
        if (!liveTimer.running)
            liveTimer.start();
    }

    Timer {
        id: liveTimer
        interval: 8
        repeat: false
        onTriggered: {
            if (root._liveDirty)
                root.rebuildLive();
        }
    }

    function rebuildLive() {
        root._liveDirty = false;
        const stroke = root.liveStroke;
        const points = stroke?.points ?? [];
        if (points.length === 0) {
            if (!root._awaitingCommit)
                root.clearLive();
            return;
        }
        livePath.variable = StrokeGeometry.isVariable(stroke);
        livePath.inkColor = stroke.color;
        livePath.inkWidth = StrokeGeometry.widthFor(stroke.width, 1, false);

        // Handed over as SVG path data: the curve renderer draws quadratic segments
        // natively, so the even stroke goes as the samples' own curves rather than as
        // the flattened polyline the canvas needs — an eighth of the vertices to
        // re-process every update.
        livePolyline.path = livePath.variable
            ? StrokeGeometry.outlineSvg(StrokeGeometry.outline(StrokeGeometry.flattened(points), stroke.width, stroke.usePressure))
            : StrokeGeometry.curveSvg(points);
        root._liveShown = true;
    }

    function clearLive() {
        root._liveShown = false;
        livePolyline.path = "";
    }

    /**
     * Draws one stroke into a context, from the same flattened geometry the live shape
     * uses: one path stroked once for an even line, the filled outline for a pressure
     * stroke. One path per stroke rather than a stroke call per segment is also simply
     * fewer calls into the rasteriser.
     */
    function paintStroke(ctx, stroke) {
        const points = stroke?.points ?? [];
        if (points.length === 0)
            return;

        const flat = StrokeGeometry.flattened(points);
        if (StrokeGeometry.isVariable(stroke)) {
            const shape = StrokeGeometry.outline(flat, stroke.width, stroke.usePressure);
            ctx.fillStyle = stroke.color;
            ctx.beginPath();
            ctx.moveTo(shape[0].x, shape[0].y);
            for (let i = 1; i < shape.length; ++i)
                ctx.lineTo(shape[i].x, shape[i].y);
            ctx.closePath();
            ctx.fill();
            return;
        }

        const width = StrokeGeometry.widthFor(stroke.width, 1, false);
        // A tap with no travel is a dot, and a dot drawn as a zero-length line is
        // nothing at all — which is how a stylus tap used to vanish.
        if (flat.length === 1) {
            ctx.fillStyle = stroke.color;
            ctx.beginPath();
            ctx.arc(flat[0].x, flat[0].y, width / 2, 0, Math.PI * 2);
            ctx.fill();
            return;
        }

        ctx.strokeStyle = stroke.color;
        ctx.lineCap = "round";
        ctx.lineJoin = "round";
        ctx.lineWidth = width;
        ctx.beginPath();
        ctx.moveTo(flat[0].x, flat[0].y);
        for (let i = 1; i < flat.length; ++i)
            ctx.lineTo(flat[i].x, flat[i].y);
        ctx.stroke();
    }

    Canvas {
        id: committed
        anchors.fill: parent
        renderStrategy: root.immediate ? Canvas.Immediate : Canvas.Cooperative
        renderTarget: root.immediate ? Canvas.Image : Canvas.FramebufferObject
        onPainted: {
            if (root._awaitingCommit && !root.liveStroke) {
                root._awaitingCommit = false;
                root.clearLive();
            }
            root.committedPainted();
        }
        onPaint: {
            const ctx = committed.getContext("2d");
            const list = root.strokes ?? [];
            let from = root._painted.length;
            if (root._repaintAll) {
                ctx.reset();
                ctx.clearRect(0, 0, committed.width, committed.height);
                from = 0;
            }
            for (let i = from; i < list.length; ++i)
                root.paintStroke(ctx, list[i]);
            root._painted = list;
            root._repaintAll = false;
        }
    }

    Shape {
        id: live
        anchors.fill: parent
        visible: root._liveShown
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            id: livePath

            property bool variable: false
            property color inkColor: "transparent"
            property real inkWidth: 1

            strokeColor: livePath.variable ? "transparent" : livePath.inkColor
            strokeWidth: livePath.variable ? -1 : livePath.inkWidth
            fillColor: livePath.variable ? livePath.inkColor : "transparent"
            fillRule: ShapePath.WindingFill
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathSvg {
                id: livePolyline
            }
        }
    }
}
