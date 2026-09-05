pragma ComponentBehavior: Bound

import QtQuick

import qs.modules.common
import "StrokeGeometry.js" as StrokeGeometry

/**
 * The ink itself: committed strokes, plus the one currently under the pen.
 *
 * Two canvases rather than one. Redrawing every stroke on every sample is fine for the
 * first page and visibly not fine by the fiftieth, so the finished strokes live on a
 * canvas that only repaints when the sheet changes, and the live stroke has a canvas of
 * its own that is cleared and redrawn each frame. What the live canvas repaints is one
 * stroke; what the committed canvas repaints is everything, and it does so rarely.
 */
Item {
    id: root

    /// [{ points: [{x,y,p}], color, width, usePressure }]
    property var strokes: []
    /// The stroke being drawn right now, or null.
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

    onStrokesChanged: committed.requestPaint()
    onWidthChanged: committed.requestPaint()
    onHeightChanged: committed.requestPaint()

    function refresh() {
        committed.requestPaint();
        live.requestPaint();
    }

    function refreshLive() {
        live.requestPaint();
    }

    /**
     * Draws one stroke into a context.
     *
     * Per-segment rather than one path for the whole stroke, because the width changes
     * along it: a single path can only be stroked at one width, so pressure would be
     * lost the moment more than two samples were joined. Round caps and joins are what
     * make the separate segments read as one line.
     */
    function paintStroke(ctx, stroke) {
        const points = stroke?.points ?? [];
        if (points.length === 0)
            return;

        ctx.strokeStyle = stroke.color;
        ctx.lineCap = "round";
        ctx.lineJoin = "round";

        // A tap with no travel is a dot, and a dot drawn as a zero-length line is
        // nothing at all — which is how a stylus tap used to vanish.
        if (points.length === 1) {
            const only = points[0];
            ctx.fillStyle = stroke.color;
            ctx.beginPath();
            ctx.arc(only.x, only.y,
                    StrokeGeometry.widthFor(stroke.width, only.p, stroke.usePressure) / 2,
                    0, Math.PI * 2);
            ctx.fill();
            return;
        }

        // The midpoint construction needs a previous end point to start from.
        let fromX = (points[0].x + points[1].x) / 2;
        let fromY = (points[0].y + points[1].y) / 2;
        ctx.beginPath();
        ctx.moveTo(points[0].x, points[0].y);
        ctx.lineTo(fromX, fromY);
        ctx.lineWidth = StrokeGeometry.widthFor(stroke.width, points[0].p, stroke.usePressure);
        ctx.stroke();

        for (let i = 1; i < points.length; ++i) {
            const segment = StrokeGeometry.quadraticSegment(
                points[i - 1], points[i], i + 1 < points.length ? points[i + 1] : null);
            ctx.beginPath();
            ctx.moveTo(fromX, fromY);
            ctx.quadraticCurveTo(segment.controlX, segment.controlY, segment.endX, segment.endY);
            ctx.lineWidth = StrokeGeometry.widthFor(stroke.width, segment.pressure, stroke.usePressure);
            ctx.stroke();
            fromX = segment.endX;
            fromY = segment.endY;
        }
    }

    Canvas {
        id: committed
        anchors.fill: parent
        renderStrategy: root.immediate ? Canvas.Immediate : Canvas.Cooperative
        renderTarget: root.immediate ? Canvas.Image : Canvas.FramebufferObject
        onPainted: root.committedPainted()
        onPaint: {
            const ctx = committed.getContext("2d");
            ctx.reset();
            ctx.clearRect(0, 0, committed.width, committed.height);
            for (const stroke of (root.strokes ?? []))
                root.paintStroke(ctx, stroke);
        }
    }

    Canvas {
        id: live
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative
        onPaint: {
            const ctx = live.getContext("2d");
            ctx.reset();
            ctx.clearRect(0, 0, live.width, live.height);
            if (root.liveStroke)
                root.paintStroke(ctx, root.liveStroke);
        }
    }
}
