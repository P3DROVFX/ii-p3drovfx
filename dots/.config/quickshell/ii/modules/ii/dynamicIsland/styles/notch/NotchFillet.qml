import QtQuick
import QtQuick.Shapes
import qs.modules.common

/**
 * The concave corner where the notch meets the screen edge.
 *
 * `radius` on a Rectangle only rounds corners *inward*, so this is drawn: a square minus
 * a quarter disc centred on its far corner. Placed just outside the island's top edge, it
 * reads as the surface flaring out into the bezel.
 *
 * The approach is taken from andreumassanet/impasto (NotchFillet.qml), which is also where
 * the proportions come from: a small fillet beside a square-topped body, rather than wide
 * concave shoulders carved out of the silhouette itself. The old shape tied the shoulder
 * width to the corner radius, so making the island rounder also made it visibly wider and
 * the curve cut *into* the content instead of away from it.
 */
Item {
    id: root

    property color color: Appearance.colors.colLayer0
    /** Mirrored for the island's left side. */
    property bool mirrored: false

    implicitWidth: Appearance.rounding.verysmall
    implicitHeight: Appearance.rounding.verysmall

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        antialiasing: true

        transform: Scale {
            xScale: root.mirrored ? -1 : 1
            origin.x: root.width / 2
        }

        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            fillColor: root.color

            startX: 0
            startY: 0

            PathLine {
                x: root.width
                y: 0
            }

            // Quarter arc around the far corner: what turns the square concave.
            PathAngleArc {
                centerX: root.width
                centerY: root.height
                radiusX: root.width
                radiusY: root.height
                startAngle: -90
                sweepAngle: -90
            }

            PathLine {
                x: 0
                y: 0
            }
        }
    }
}
