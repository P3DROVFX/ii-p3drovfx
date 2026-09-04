pragma ComponentBehavior: Bound

import QtQuick

import qs.modules.common
import "StrokeGeometry.js" as StrokeGeometry

/**
 * A sheet you can draw on: the ink, the pen, and the bookkeeping between them.
 *
 * Everything about turning pointer samples into strokes lives here, so the two places
 * that draw — a sheet floating over a workspace, and a sketch inside a note — share it
 * rather than each keeping their own copy of the smoothing, the thinning and the live
 * stroke. What differs between them is where the strokes are *stored*, which is the
 * host's business: this emits `strokeFinished` and `eraseRequested` and holds nothing.
 */
Item {
    id: root

    /// The committed strokes to paint. The host owns the list.
    property var strokes: []

    /// Whether the pen is down. False leaves the ink painted and takes no input.
    property bool drawing: false

    // ── Tools ───────────────────────────────────────────────────────────────
    property string color: "#ffffff"
    property real strokeWidth: 4
    property bool usePressure: true
    /// 0..0.95. See StrokeGeometry.smoothed.
    property real smoothing: 0.55
    property bool eraser: false
    readonly property real eraserRadius: Math.max(20, root.strokeWidth * 3)

    /**
     * An item whose area the pen must ignore, or null.
     *
     * The toolbar floats over the sheet, and without this the drawing surface accepted
     * every tablet event that landed on it — so a pen tap on Undo was swallowed by the
     * canvas and arrived as a stroke, while the same tap with a mouse worked. Qt only
     * synthesises a mouse event from a tablet event that nothing accepted, so declining
     * the point here is what lets the toolbar's own handlers see it.
     */
    property Item excludeItem: null

    /// True once a device has reported a pressure strictly between the ends, which is a
    /// device that is actually measuring rather than a mouse reporting 1.
    property bool penSeen: false

    signal strokeFinished(var stroke)
    signal eraseRequested(real x, real y)

    // ── The live stroke ─────────────────────────────────────────────────────
    property var livePoints: []
    property var smoothPoint: null

    function currentStrokeRecord() {
        return {
            points: root.livePoints,
            color: root.color,
            width: root.strokeWidth,
            usePressure: root.usePressure
        };
    }

    function beginStroke(x, y, pressure) {
        const first = StrokeGeometry.point(x, y, pressure);
        root.smoothPoint = first;
        root.livePoints = [first];
        canvas.liveStroke = root.currentStrokeRecord();
        canvas.refreshLive();
    }

    function extendStroke(x, y, pressure) {
        if (root.livePoints.length === 0)
            return;
        const raw = StrokeGeometry.point(x, y, pressure);
        // Smoothed before the distance test, so the filter sees every sample and the
        // thinning only decides what is worth keeping afterwards.
        root.smoothPoint = StrokeGeometry.smoothed(root.smoothPoint, raw, root.smoothing);
        const last = root.livePoints[root.livePoints.length - 1];
        if (!StrokeGeometry.shouldAppend(last, root.smoothPoint))
            return;
        root.livePoints = root.livePoints.concat([root.smoothPoint]);
        canvas.liveStroke = root.currentStrokeRecord();
        canvas.refreshLive();
    }

    function endStroke() {
        if (root.livePoints.length > 0)
            root.strokeFinished(root.currentStrokeRecord());
        root.livePoints = [];
        root.smoothPoint = null;
        canvas.liveStroke = null;
        canvas.refreshLive();
    }

    /// Drops a stroke in progress without committing it. For a host that leaves drawing
    /// mode mid-stroke.
    function abandonStroke() {
        root.livePoints = [];
        root.smoothPoint = null;
        canvas.liveStroke = null;
        canvas.refreshLive();
    }

    onDrawingChanged: if (!root.drawing) root.abandonStroke()

    /// Grabs the painted ink. See DrawCanvas.saveCommitted.
    function saveTo(path) {
        canvas.saveCommitted(path);
    }
    signal saved(bool ok, string path)

    // ── Painting ────────────────────────────────────────────────────────────
    DrawCanvas {
        id: canvas
        anchors.fill: parent
        strokes: root.strokes
        onSaved: (ok, path) => root.saved(ok, path)
    }

    /**
     * Where the pen's area actually is.
     *
     * A `containmentMask` rather than a smaller item, because the ink has to cover the
     * whole sheet and only the *input* has a hole in it. Qt asks this before delivering a
     * point to this item or any of its handlers, so declining here means the event
     * carries on to whatever is in front — the toolbar — exactly as if the canvas were
     * not there.
     */
    containmentMask: QtObject {
        function contains(point: point): bool {
            if (!root.drawing)
                return false;
            const exclude = root.excludeItem;
            if (!exclude || !exclude.visible)
                return true;
            const local = exclude.mapFromItem(root, point.x, point.y);
            const inside = local.x >= 0 && local.y >= 0
                && local.x <= exclude.width && local.y <= exclude.height;
            return !inside;
        }
    }

    /**
     * The pen.
     *
     * A PointHandler rather than a MouseArea, because a MouseArea reports no pressure:
     * Qt delivers a stylus as a pointer device with a `pressure` on each point, and that
     * is the number OpenTabletDriver spends its whole existence producing. Fingers and
     * the mouse arrive through the same handler and report pressure 1, which is the right
     * answer for them — a finger has no pressure to report and its stroke should be even.
     *
     * The eraser end of a stylus is a distinct pointer type, so turning the pen over rubs
     * out without going near the toolbar.
     */
    PointHandler {
        id: pen
        enabled: root.drawing

        readonly property bool eraserTip: pen.point.device?.pointerType === PointerDevice.Eraser
        readonly property bool erasing: pen.eraserTip || root.eraser

        /// Measured from the values rather than asked of the device: a mouse and a finger
        /// both report exactly 1, and anything strictly between the ends is a device that
        /// is actually measuring. That test needs no enum spelled correctly and no
        /// assumption about how the driver presents itself.
        function noteDevice() {
            const pressure = pen.point.pressure;
            if (pressure > 0.001 && pressure < 0.999)
                root.penSeen = true;
            if (pen.point.device?.pointerType === PointerDevice.Pen
                    || pen.point.device?.pointerType === PointerDevice.Eraser)
                root.penSeen = true;
        }

        onActiveChanged: {
            if (pen.active) {
                pen.noteDevice();
                if (pen.erasing)
                    root.eraseRequested(pen.point.position.x, pen.point.position.y);
                else
                    root.beginStroke(pen.point.position.x, pen.point.position.y, pen.point.pressure);
            } else if (root.livePoints.length > 0) {
                root.endStroke();
            }
        }

        onPointChanged: {
            if (!pen.active)
                return;
            pen.noteDevice();
            if (pen.erasing)
                root.eraseRequested(pen.point.position.x, pen.point.position.y);
            else
                root.extendStroke(pen.point.position.x, pen.point.position.y, pen.point.pressure);
        }
    }
}
