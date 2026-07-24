import QtQuick
import QtQuick.Shapes

// Straight line annotation: the arrow renderer minus the arrowhead.
Shape {
    id: lineRoot
    property var annData: null
    readonly property var g: annData ? (annData.geom ?? annData) : null
    readonly property var s: annData ? (annData.style ?? annData) : null
    readonly property color strokeColor: s?.stroke ?? s?.color ?? "transparent"
    readonly property real strokeW: s?.strokeWidth ?? s?.lineWidth ?? 2
    readonly property real x1: g?.x1 ?? 0
    readonly property real y1: g?.y1 ?? 0
    readonly property real x2: g?.x2 ?? 0
    readonly property real y2: g?.y2 ?? 0

    x: Math.min(x1, x2) - 20
    y: Math.min(y1, y2) - 20
    width: Math.abs(x2 - x1) + 40
    height: Math.abs(y2 - y1) + 40
    opacity: s?.opacity ?? 1
    visible: annData !== null

    ShapePath {
        strokeColor: lineRoot.strokeColor
        strokeWidth: lineRoot.strokeW
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap

        startX: lineRoot.x1 - lineRoot.x
        startY: lineRoot.y1 - lineRoot.y

        PathLine {
            x: lineRoot.x2 - lineRoot.x
            y: lineRoot.y2 - lineRoot.y
        }
    }
}
