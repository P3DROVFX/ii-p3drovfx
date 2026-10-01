pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

/**
 * The island's silhouette as one antialiased path: body, bottom corners and the
 * concave shoulders that flare into the screen edge.
 *
 * The shoulders used to be two separate `NotchFillet` items butted against the
 * body's sides. Two items that share an edge are antialiased separately, so the
 * shared column is covered twice at ~50% and never reaches full opacity: a thin
 * line down the junction, exactly where the silhouette should read as one
 * object. Overlapping the fillets into the body hides it while the fill is
 * opaque and brings it back as a double blend the moment the layer is
 * translucent, so the only structural answer is one path - which is what this
 * is. The approach (and the name) comes from the aesteria shell's NotchShape;
 * the curvature stays this shell's: circular quarter arcs of `shoulder`
 * radius, not quadratic beziers.
 *
 * Both shells of the island use the same item. Attached to the edge
 * (`attached`), the top corners are the concave flares and the straight sides
 * sit `shoulder` in from the item's edges. As a floating pill, the same inset
 * keeps the visible body the width of the content clip, only the top corners
 * turn convex (`topRadius`). Reserving the inset in both shells is what keeps
 * every width measured elsewhere - content clip, bubble necks, the bar's
 * centre gap - the straight body's width, unchanged.
 */
Item {
    id: root

    /**
     * Room the concave shoulders take on each side, and the inset of the
     * straight body in both shells. Clamped here so a retracting or morphing
     * surface can never ask an arc for more room than the shape has.
     */
    property real shoulder: 0

    /** Concave flares into the screen edge, rather than convex top corners. */
    property bool attached: false

    /** Convex top corners, used while not attached. */
    property real topRadius: 0

    /** Convex bottom corners; also the body's rounding, read back as `bodyRadius`. */
    property real bottomRadius: 0
    readonly property alias bodyRadius: root.bottomRadius

    property color color: "black"

    /** The straight part of the silhouette: what content and bubbles measure. */
    readonly property real bodyWidth: Math.max(0, root.width - 2 * root.clampedShoulder)

    readonly property real clampedShoulder: Math.min(root.shoulder, root.height, root.width / 2)
    readonly property real clampedTop: Math.min(root.topRadius, root.height / 2, Math.max(0, root.width / 2 - root.clampedShoulder))
    readonly property real clampedBottom: Math.min(root.bottomRadius, root.height / 2, Math.max(0, root.width / 2 - root.clampedShoulder))

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        antialiasing: true

        ShapePath {
            id: path
            strokeWidth: 0
            strokeColor: "transparent"
            fillColor: root.color

            // Shorthand for the bound geometry below.
            readonly property real s: root.clampedShoulder
            readonly property real tr: root.clampedTop
            readonly property real br: root.clampedBottom
            readonly property real xL: path.s
            readonly property real xR: root.width - path.s
            /** Where the straight sides begin: below the flare, or below the convex cap. */
            readonly property real topY: root.attached ? path.s : path.tr

            startX: root.attached ? 0 : path.xL + path.tr
            startY: 0

            // Top edge, between the two top corners.
            PathLine {
                x: root.attached ? root.width : path.xR - path.tr
                y: 0
            }

            // Top-right: concave flare out to the edge, or convex cap of the pill.
            PathAngleArc {
                moveToStart: false
                centerX: root.attached ? root.width : path.xR - path.tr
                centerY: root.attached ? path.s : path.tr
                radiusX: root.attached ? path.s : path.tr
                radiusY: root.attached ? path.s : path.tr
                startAngle: -90
                sweepAngle: root.attached ? -90 : 90
            }

            PathLine {
                x: path.xR
                y: root.height - path.br
            }

            PathAngleArc {
                moveToStart: false
                centerX: path.xR - path.br
                centerY: root.height - path.br
                radiusX: path.br
                radiusY: path.br
                startAngle: 0
                sweepAngle: 90
            }

            PathLine {
                x: path.xL + path.br
                y: root.height
            }

            PathAngleArc {
                moveToStart: false
                centerX: path.xL + path.br
                centerY: root.height - path.br
                radiusX: path.br
                radiusY: path.br
                startAngle: 90
                sweepAngle: 90
            }

            PathLine {
                x: path.xL
                y: path.topY
            }

            // Top-left, mirroring the top-right corner.
            PathAngleArc {
                moveToStart: false
                centerX: root.attached ? 0 : path.xL + path.tr
                centerY: root.attached ? path.s : path.tr
                radiusX: root.attached ? path.s : path.tr
                radiusY: root.attached ? path.s : path.tr
                startAngle: root.attached ? 0 : 180
                sweepAngle: root.attached ? -90 : 90
            }
        }
    }
}
