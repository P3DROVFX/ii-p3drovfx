import QtQuick
import QtQuick.Shapes

// Arrow annotation: a line plus a filled arrowhead at (x2, y2).
Shape {
    id: arrowRoot
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
    visible: annData !== null

    ShapePath {
        strokeColor: arrowRoot.strokeColor
        strokeWidth: arrowRoot.strokeW
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap

        startX: arrowRoot.x1 - arrowRoot.x
        startY: arrowRoot.y1 - arrowRoot.y

        PathLine {
            x: arrowRoot.x2 - arrowRoot.x
            y: arrowRoot.y2 - arrowRoot.y
        }
    }
    ShapePath {
        strokeColor: "transparent"
        fillColor: arrowRoot.strokeColor

        startX: arrowRoot.x2 - arrowRoot.x
        startY: arrowRoot.y2 - arrowRoot.y

        PathLine {
            x: (arrowRoot.x2 - arrowRoot.x) - Math.max(15, arrowRoot.strokeW * 3) * Math.cos(Math.atan2(arrowRoot.y2 - arrowRoot.y1, arrowRoot.x2 - arrowRoot.x1) - Math.PI / 6)
            y: (arrowRoot.y2 - arrowRoot.y) - Math.max(15, arrowRoot.strokeW * 3) * Math.sin(Math.atan2(arrowRoot.y2 - arrowRoot.y1, arrowRoot.x2 - arrowRoot.x1) - Math.PI / 6)
        }
        PathLine {
            x: (arrowRoot.x2 - arrowRoot.x) - Math.max(15, arrowRoot.strokeW * 3) * Math.cos(Math.atan2(arrowRoot.y2 - arrowRoot.y1, arrowRoot.x2 - arrowRoot.x1) + Math.PI / 6)
            y: (arrowRoot.y2 - arrowRoot.y) - Math.max(15, arrowRoot.strokeW * 3) * Math.sin(Math.atan2(arrowRoot.y2 - arrowRoot.y1, arrowRoot.x2 - arrowRoot.x1) + Math.PI / 6)
        }
        PathLine {
            x: arrowRoot.x2 - arrowRoot.x
            y: arrowRoot.y2 - arrowRoot.y
        }
    }
}
