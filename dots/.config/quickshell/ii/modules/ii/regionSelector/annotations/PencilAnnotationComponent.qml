import QtQuick
import QtQuick.Shapes
import "../../../common/draw/StrokeGeometry.js" as StrokeGeometry

// Freehand pencil (and highlighter) stroke, drawn by live draw's engine: the smoothed
// midpoint curves for an even line, the filled outline of a pen-pressure stroke. The
// Shape spans the whole editor canvas so its path coordinates stay in editor-local
// space; the caller passes the canvas size.
Shape {
    id: pencilRoot
    property var annData: null
    property real canvasWidth: 4000
    property real canvasHeight: 4000
    readonly property var s: annData ? (annData.style ?? annData) : null
    readonly property var svg: {
        if (!pencilRoot.annData)
            return ({ "d": "", "filled": false });
        // Legacy flat dicts: points at the top level, no style object.
        const ann = pencilRoot.annData.geom ? pencilRoot.annData : ({
            "type": "pencil",
            "geom": { "points": pencilRoot.annData.points ?? [] },
            "style": { "stroke": pencilRoot.annData.color, "strokeWidth": pencilRoot.annData.lineWidth ?? 2 }
        });
        return StrokeGeometry.strokeSvg(AnnotationModel.strokeOf(ann));
    }

    x: 0
    y: 0
    width: canvasWidth
    height: canvasHeight
    // Highlighter strokes reuse this renderer with a reduced style.opacity.
    opacity: s?.opacity ?? 1
    visible: annData !== null
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        readonly property color ink: pencilRoot.s?.stroke ?? pencilRoot.s?.color ?? "transparent"
        strokeColor: pencilRoot.svg.filled ? "transparent" : ink
        strokeWidth: pencilRoot.svg.filled ? -1 : (pencilRoot.s?.strokeWidth ?? pencilRoot.s?.lineWidth ?? 2)
        fillColor: pencilRoot.svg.filled ? ink : "transparent"
        fillRule: ShapePath.WindingFill
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin

        PathSvg {
            path: pencilRoot.svg.d
        }
    }
}
