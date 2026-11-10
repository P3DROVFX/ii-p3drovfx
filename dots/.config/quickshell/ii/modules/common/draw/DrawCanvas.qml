pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

import qs.modules.common
import "StrokeGeometry.js" as StrokeGeometry

/**
 * The ink itself: committed strokes, the one currently under the pen, and the laser.
 *
 * Each renderer does only what it is cheap at.
 *
 * The finished strokes live on canvases painted *incrementally*: a stroke that was just
 * added is drawn on top of what is already there, and only an undo, an erase or a new
 * sheet clears and repaints. Highlighter strokes have a canvas of their own *under* the
 * ink, so a marker pass over handwriting never covers it — and that canvas only exists
 * while the sheet has a highlighter stroke on it, since each is a screen-sized image.
 *
 * The stroke under the pen is a vector `Shape`, not another canvas: a canvas is a
 * screen-sized image re-uploaded on every change, the shape is a handful of vertices the
 * GPU strokes and antialiases. It is rebuilt at most once per ~8 ms however fast the
 * device reports. A live highlighter stroke has its own shape under the ink too.
 *
 * The laser is a trail that is never committed: each stroke is a shape that fades out
 * and is destroyed.
 *
 * Every renderer draws the same geometry (StrokeGeometry), so a stroke does not move
 * when it is handed from one to the other.
 */
Item {
    id: root

    /// [{ tool, points: [{x,y,p}], color, width, usePressure }]
    property var strokes: []
    /// The stroke being drawn right now, or null. Its `points` array may grow in place;
    /// call `refreshLive()` after changing it.
    property var liveStroke: null

    /// Paint in the GUI thread and into an image. Only the offscreen crop needs this: it
    /// is what a grab can read back from straight away.
    property bool immediate: false

    /// How long a laser stroke stays before it starts to fade, and how long the fade is.
    property int laserHoldMs: 700
    property int laserFadeMs: 900

    /// The finished strokes have been painted. What a save waits for — a Canvas paints
    /// when the scene graph gets to it, so writing straight after requesting a repaint
    /// wrote a blank file.
    signal committedPainted()

    /// Emitted once a `saveCommitted` has finished, with whether the file was written.
    signal saved(bool ok, string path)

    /**
     * Writes the finished strokes to `path` as a PNG with a transparent background.
     * Asynchronous; watch `saved`.
     *
     * Grabbed rather than saved through `Canvas.save`: under Quickshell every
     * component's base URL is a `qs:` URL, so `Canvas.save` resolves an absolute path
     * into nothing. A grab result takes the URL as given.
     */
    function saveCommitted(path) {
        const target = String(path ?? "");
        const grabbed = inkStack.grabToImage(result => {
            root.saved(result.saveToFile(`file://${target}`), target);
        });
        if (!grabbed)
            root.saved(false, target);
    }

    // ── The layers ──────────────────────────────────────────────────────────
    readonly property var highlightStrokes: (root.strokes ?? []).filter(s => StrokeGeometry.toolOf(s) === "highlighter")
    readonly property var inkStrokes: (root.strokes ?? []).filter(s => StrokeGeometry.toolOf(s) !== "highlighter")

    onWidthChanged: root.refresh()
    onHeightChanged: root.refresh()

    function refresh() {
        committed.repaintAll();
        underLoader.item?.repaintAll();
        root.refreshLive();
    }

    // ── The live stroke ─────────────────────────────────────────────────────
    /// The live stroke changed. Rebuilt at most once per ~8 ms, however many samples
    /// arrived in between.
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

    /// A stroke just handed over from the pen: the shape keeps showing it until a canvas
    /// has painted it, or the line would blink out for a frame in between.
    onStrokesChanged: {
        if (root.liveStroke)
            root._awaitingCommit = true;
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

        const tool = StrokeGeometry.toolOf(stroke);
        if (tool === "laser") {
            liveOver.show(stroke, StrokeGeometry.strokeSvg(stroke), 1);
            liveUnder.hide();
            root._liveShown = true;
            return;
        }
        const svg = StrokeGeometry.strokeSvg(stroke);
        if (tool === "highlighter") {
            liveUnder.show(stroke, svg, StrokeGeometry.alphaOf(stroke));
            liveOver.hide();
        } else {
            liveOver.show(stroke, svg, 1);
            liveUnder.hide();
        }
        root._liveShown = true;
    }

    function clearLive() {
        root._liveShown = false;
        liveOver.hide();
        liveUnder.hide();
    }

    function _committedPainted() {
        if (committed.pending || (underLoader.item?.pending ?? false))
            return;
        if (root._awaitingCommit && !root.liveStroke) {
            root._awaitingCommit = false;
            root.clearLive();
        }
        root.committedPainted();
    }

    // ── The laser ───────────────────────────────────────────────────────────
    /// Hands a finished laser stroke to the fading trail. It is never committed.
    function releaseLaser(stroke) {
        const svg = StrokeGeometry.strokeSvg(stroke);
        if (svg.d.length > 0)
            laserTrail.append({ path: svg.d, ink: String(stroke.color), lineWidth: StrokeGeometry.drawnWidth(stroke) });
        root.clearLive();
    }

    // ── Painting a stroke into a canvas ─────────────────────────────────────
    /**
     * Draws one stroke into a context, from the same geometry the live shape uses: one
     * path stroked once for an even line or a shape, the filled outline for a pressure
     * stroke.
     */
    function paintStroke(ctx, stroke) {
        const points = stroke?.points ?? [];
        if (points.length === 0)
            return;

        ctx.globalAlpha = StrokeGeometry.alphaOf(stroke);
        ctx.lineCap = "round";
        ctx.lineJoin = "round";

        if (StrokeGeometry.isShape(stroke)) {
            ctx.strokeStyle = stroke.color;
            ctx.lineWidth = StrokeGeometry.drawnWidth(stroke);
            ctx.beginPath();
            for (const line of StrokeGeometry.shapePolylines(stroke)) {
                ctx.moveTo(line[0].x, line[0].y);
                for (let i = 1; i < line.length; ++i)
                    ctx.lineTo(line[i].x, line[i].y);
            }
            ctx.stroke();
            ctx.globalAlpha = 1;
            return;
        }

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
            ctx.globalAlpha = 1;
            return;
        }

        const width = StrokeGeometry.drawnWidth(stroke);
        // A tap with no travel is a dot, and a dot drawn as a zero-length line is
        // nothing at all — which is how a stylus tap used to vanish.
        if (flat.length === 1) {
            ctx.fillStyle = stroke.color;
            ctx.beginPath();
            ctx.arc(flat[0].x, flat[0].y, width / 2, 0, Math.PI * 2);
            ctx.fill();
            ctx.globalAlpha = 1;
            return;
        }

        ctx.strokeStyle = stroke.color;
        ctx.lineWidth = width;
        ctx.beginPath();
        ctx.moveTo(flat[0].x, flat[0].y);
        for (let i = 1; i < flat.length; ++i)
            ctx.lineTo(flat[i].x, flat[i].y);
        ctx.stroke();
        ctx.globalAlpha = 1;
    }

    /// A canvas that paints only what was appended since its last paint.
    component InkCanvas: Canvas {
        id: inkCanvas
        property var list: []
        property var _painted: []
        property bool _repaintAll: true
        /// A paint was asked for and has not landed yet. A save waits for every layer.
        property bool pending: false

        function repaintAll() {
            inkCanvas._repaintAll = true;
            inkCanvas.paintSoon();
        }

        function paintSoon() {
            inkCanvas.pending = true;
            inkCanvas.requestPaint();
        }

        Component.onCompleted: inkCanvas.repaintAll()

        onListChanged: {
            const next = inkCanvas.list ?? [];
            const previous = inkCanvas._painted;
            // Appended to, with everything before untouched: paint just the new strokes.
            // Anything else — an undo, an erase, another sheet — starts over.
            let appended = !inkCanvas._repaintAll && next.length >= previous.length;
            for (let i = 0; appended && i < previous.length; ++i)
                appended = next[i] === previous[i];
            if (appended && next.length === previous.length)
                return;
            if (!appended)
                inkCanvas._repaintAll = true;
            inkCanvas.paintSoon();
        }

        anchors.fill: parent
        renderStrategy: root.immediate ? Canvas.Immediate : Canvas.Cooperative
        renderTarget: root.immediate ? Canvas.Image : Canvas.FramebufferObject
        onPaint: {
            const ctx = inkCanvas.getContext("2d");
            const list = inkCanvas.list ?? [];
            let from = inkCanvas._painted.length;
            if (inkCanvas._repaintAll) {
                ctx.reset();
                ctx.clearRect(0, 0, inkCanvas.width, inkCanvas.height);
                from = 0;
            }
            for (let i = from; i < list.length; ++i)
                root.paintStroke(ctx, list[i]);
            inkCanvas._painted = list;
            inkCanvas._repaintAll = false;
        }
        onPainted: {
            inkCanvas.pending = false;
            root._committedPainted();
        }
    }

    /// One live vector stroke.
    component LiveShape: Shape {
        id: liveShape
        property bool filled: false
        property color ink: "transparent"
        property real lineWidth: 1

        function show(stroke, svg, alpha) {
            liveShape.filled = svg.filled;
            liveShape.ink = Qt.alpha(stroke.color, alpha);
            liveShape.lineWidth = StrokeGeometry.drawnWidth(stroke);
            livePath.path = svg.d;
            liveShape.visible = true;
        }

        function hide() {
            liveShape.visible = false;
            livePath.path = "";
        }

        anchors.fill: parent
        visible: false
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: liveShape.filled ? "transparent" : liveShape.ink
            strokeWidth: liveShape.filled ? -1 : liveShape.lineWidth
            fillColor: liveShape.filled ? liveShape.ink : "transparent"
            fillRule: ShapePath.WindingFill
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathSvg {
                id: livePath
            }
        }
    }

    // Everything a save takes: the highlighter under the ink, and the ink.
    Item {
        id: inkStack
        anchors.fill: parent

        Loader {
            id: underLoader
            anchors.fill: parent
            active: root.highlightStrokes.length > 0 || liveUnder.visible
            sourceComponent: InkCanvas {
                list: root.highlightStrokes
            }
        }

        LiveShape {
            id: liveUnder
        }

        InkCanvas {
            id: committed
            list: root.inkStrokes
        }
    }

    LiveShape {
        id: liveOver
    }

    // ── The laser's trail ───────────────────────────────────────────────────
    ListModel {
        id: laserTrail
    }

    Repeater {
        model: laserTrail

        delegate: Shape {
            id: fading
            required property string path
            required property string ink
            required property real lineWidth
            required property int index

            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: fading.ink
                strokeWidth: fading.lineWidth
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg {
                    path: fading.path
                }
            }

            SequentialAnimation on opacity {
                running: true
                PauseAnimation {
                    duration: root.laserHoldMs
                }
                NumberAnimation {
                    to: 0
                    duration: root.laserFadeMs
                    easing.type: Easing.InCubic
                }
                // Gone once invisible. The oldest goes first, and every stroke fades for
                // the same time, so the faded one is always at the front of the list.
                ScriptAction {
                    script: Qt.callLater(() => {
                        if (laserTrail.count > 0)
                            laserTrail.remove(0);
                    })
                }
            }
        }
    }
}
