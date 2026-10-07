import QtQuick
import QtQuick.Shapes

// Ellipse inscribed in a dragged box — live draw's ellipse in the screenshot editor.
// A Shape rather than a rounded Rectangle: a rectangle's radius makes a pill, not an
// ellipse, as soon as the box stops being square.
Shape {
    id: ellipseRoot
    property var annData: null
    readonly property var g: annData ? (annData.geom ?? annData) : null
    readonly property var s: annData ? (annData.style ?? annData) : null
    readonly property real strokeW: s?.strokeWidth ?? 2

    // Grown by half the stroke on every side, so the outline is never clipped.
    x: (g?.x ?? 0) - ellipseRoot.strokeW
    y: (g?.y ?? 0) - ellipseRoot.strokeW
    width: (g?.w ?? 0) + ellipseRoot.strokeW * 2
    height: (g?.h ?? 0) + ellipseRoot.strokeW * 2
    opacity: s?.opacity ?? 1
    visible: annData !== null
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeColor: ellipseRoot.s?.stroke ?? "transparent"
        strokeWidth: ellipseRoot.strokeW
        fillColor: {
            if (!ellipseRoot.s || !ellipseRoot.s.fill)
                return "transparent";
            const c = Qt.color(ellipseRoot.s.fill);
            return Qt.rgba(c.r, c.g, c.b, ellipseRoot.s.fillOpacity ?? 0.25);
        }

        PathAngleArc {
            centerX: ellipseRoot.width / 2
            centerY: ellipseRoot.height / 2
            radiusX: Math.max(0, (ellipseRoot.g?.w ?? 0) / 2)
            radiusY: Math.max(0, (ellipseRoot.g?.h ?? 0) / 2)
            startAngle: 0
            sweepAngle: 360
        }
    }
}
