import QtQuick
import QtQuick.Shapes

// Freehand pencil stroke. The Shape spans the whole editor canvas so its
// path coordinates stay in editor-local space; the caller passes the canvas
// size (previously read off editorContent directly).
Shape {
    id: pencilRoot
    property var annData: null
    property real canvasWidth: 4000
    property real canvasHeight: 4000
    readonly property var g: annData ? (annData.geom ?? annData) : null
    readonly property var s: annData ? (annData.style ?? annData) : null

    x: 0
    y: 0
    width: canvasWidth
    height: canvasHeight
    visible: annData !== null

    ShapePath {
        strokeColor: pencilRoot.s?.stroke ?? pencilRoot.s?.color ?? "transparent"
        strokeWidth: pencilRoot.s?.strokeWidth ?? pencilRoot.s?.lineWidth ?? 2
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin

        PathSvg {
            path: {
                var pts = pencilRoot.g?.points;
                if (!pts || pts.length === 0)
                    return "";
                var d = "M " + pts[0].x + " " + pts[0].y;
                for (var i = 1; i < pts.length - 2; i++) {
                    var xc = (pts[i].x + pts[i + 1].x) / 2;
                    var yc = (pts[i].y + pts[i + 1].y) / 2;
                    d += " Q " + pts[i].x + " " + pts[i].y + ", " + xc + " " + yc;
                }
                if (pts.length > 2) {
                    d += " Q " + pts[pts.length - 2].x + " " + pts[pts.length - 2].y + ", " + pts[pts.length - 1].x + " " + pts[pts.length - 1].y;
                } else if (pts.length === 2) {
                    d += " L " + pts[1].x + " " + pts[1].y;
                }
                return d;
            }
        }
    }
}
