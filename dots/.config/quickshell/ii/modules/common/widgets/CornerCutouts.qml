import QtQuick
import QtQuick.Shapes

/**
 * Four corner pieces in the background colour, so a plainly clipped item
 * (`clip: true`) reads as rounded.
 *
 * A layer mask (OpacityMask, ClippingRectangle) renders the whole content into
 * an offscreen texture and redraws it on every change. These cost neither, but
 * they only hide the corners over an opaque background of `color` - keep the
 * mask for translucent surfaces.
 */
Item {
    id: root

    property real radius: 0
    property color color: "black"

    visible: radius > 0

    component Corner: Shape {
        id: corner
        readonly property real r: root.radius

        width: r
        height: r
        preferredRendererType: Shape.CurveRenderer

        // One pixel past the item's edges, so antialiasing along the clip
        // line cannot leave a hairline of content showing.
        ShapePath {
            strokeWidth: -1
            fillColor: root.color
            startX: -1
            startY: -1
            PathLine { x: corner.r; y: -1 }
            PathLine { x: corner.r; y: 0 }
            PathArc {
                x: 0
                y: corner.r
                radiusX: corner.r
                radiusY: corner.r
                direction: PathArc.Counterclockwise
            }
            PathLine { x: -1; y: corner.r }
            PathLine { x: -1; y: -1 }
        }
    }

    Corner {
        anchors.top: parent.top
        anchors.left: parent.left
    }

    Corner {
        anchors.top: parent.top
        anchors.right: parent.right
        rotation: 90
    }

    Corner {
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        rotation: 180
    }

    Corner {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        rotation: 270
    }
}
