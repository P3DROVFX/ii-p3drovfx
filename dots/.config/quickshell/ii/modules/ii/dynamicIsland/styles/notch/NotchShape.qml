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

    /**
     * The sculpted shell: each side is one long S instead of a small concave
     * arc plus a round corner. Only drawn while `attached`; the top edge flares
     * out over `shoulder`, the curve turns at the straight body's edge and the
     * bottom corner eases back in over `foot`, so the bottom run is
     * `bodyWidth - 2 * foot` wide.
     *
     * At rest the side is a single cubic S, kept as its two halves (split at
     * the inflection) so that a tall face can pull them apart: the flare stays
     * `flareDepth` deep, the corner keeps `bottomRadius`, and a straight run
     * joins them. `slant` (0-1) leans that shared tangent: 1 is the S's own
     * lean, 0 stands it upright for straight sides. The halves' handles are
     * those of the split, so the tangent never leans past what the handles
     * can turn and the curve cannot ripple.
     */
    property bool sculpted: false
    /** Vertical room the top flare takes; the rest of the side belongs to the corner. */
    property real flareDepth: 0
    /** How far the bottom corner reaches in from the straight body's edge. */
    property real foot: 0
    /** Lean of the S at its inflection: 1 is the full S, 0 is upright. */
    property real slant: 1
    /** Handle length along the edges, as a share of each half's width; lower is a longer, straighter middle. */
    property real tension: 0.58
    readonly property bool sculptedPath: root.sculpted && root.attached

    /** The straight part of the silhouette: what content and bubbles measure. */
    readonly property real bodyWidth: Math.max(0, root.width - 2 * root.clampedShoulder)

    readonly property real clampedShoulder: Math.min(root.shoulder, root.height, root.width / 2)
    readonly property real clampedTop: Math.min(root.topRadius, root.height / 2, Math.max(0, root.width / 2 - root.clampedShoulder))
    readonly property real clampedBottom: Math.min(root.bottomRadius, root.height / 2, Math.max(0, root.width / 2 - root.clampedShoulder))

    /**
     * The sculpted silhouette as an SVG path: the halves of each S and the
     * straight run between them depend on one another, which a declarative
     * path would spell out twice per side.
     */
    /**
     * The sculpted side's control points, right side, top to bottom (the left
     * mirrors it): the flare cubic p0-c1-c2-j1, the straight run j1-j2 and the
     * corner cubic j2-c3-c4-fo. Null while the path is not drawn.
     */
    readonly property var sculptedGeometry: {
        if (!root.sculptedPath)
            return null;
        const w = root.width;
        const h = root.height;
        const s = root.clampedShoulder;
        if (w <= 0 || h <= 0)
            return null;
        // The corner keeps its share first, the flare takes what is left above it.
        const b = Math.min(root.bottomRadius, h / 2);
        const a = Math.max(0, Math.min(root.flareDepth > 0 ? root.flareDepth : h / 2, h - b));
        const run = Math.max(0, h - b - a);
        const foot = Math.max(0, Math.min(root.foot, (w - 2 * s) / 2 - 0.5));
        const k = root.tension;
        // The S's own lean, from the half that can turn the least.
        const t = Math.max(0, Math.min(1, root.slant)) * (1 - k)
            * Math.min(a > 0 ? s / a : 0, b > 0 ? foot / b : 0);
        const j1x = w - s, j1y = a;
        const j2x = j1x - t * run, j2y = h - b;
        const fx = j2x - foot;
        return { w: w, h: h,
            p0: [w, 0], c1: [w - k * s, 0], c2: [j1x + 0.5 * a * t, j1y - 0.5 * a], j1: [j1x, j1y],
            j2: [j2x, j2y], c3: [j2x - 0.5 * b * t, j2y + 0.5 * b], c4: [fx + k * foot, h], fo: [fx, h] };
    }

    readonly property string sculptedSvg: {
        const g = root.sculptedGeometry;
        if (!g)
            return "";
        const w = g.w;
        const f = v => v.toFixed(2);
        const pt = q => f(q[0]) + " " + f(q[1]);
        const mirror = q => [w - q[0], q[1]];
        const L = {};
        for (const key of ["p0", "c1", "c2", "j1", "j2", "c3", "c4", "fo"])
            L[key] = mirror(g[key]);
        return "M " + pt(L.p0) + " L " + pt(g.p0)
            + " C " + pt(g.c1) + " " + pt(g.c2) + " " + pt(g.j1)
            + " L " + pt(g.j2)
            + " C " + pt(g.c3) + " " + pt(g.c4) + " " + pt(g.fo)
            + " L " + pt(L.fo)
            + " C " + pt(L.c4) + " " + pt(L.c3) + " " + pt(L.j2)
            + " L " + pt(L.j1)
            + " C " + pt(L.c2) + " " + pt(L.c1) + " " + pt(L.p0) + " Z";
    }

    /**
     * Half the silhouette's width at height `y`, measured from the centre: what a
     * hit test or a neighbour placed beside the island has to clear. Exact for the
     * sculpted S (sampled from its cubics); the item's half width otherwise.
     */
    function halfWidthAt(y: real): real {
        const g = root.sculptedGeometry;
        if (!g)
            return root.width / 2;
        if (y <= 0)
            return g.w / 2;
        if (y >= g.h)
            return g.w / 2 - (g.w - g.fo[0]);
        const bez = (p0, p1, p2, p3, u) => {
            const v = 1 - u;
            return [v * v * v * p0[0] + 3 * v * v * u * p1[0] + 3 * v * u * u * p2[0] + u * u * u * p3[0],
                v * v * v * p0[1] + 3 * v * v * u * p1[1] + 3 * v * u * u * p2[1] + u * u * u * p3[1]];
        };
        // Each cubic's y rises monotonically, so a bisection on its parameter finds y.
        const solve = (p0, p1, p2, p3) => {
            let lo = 0, hi = 1;
            for (let i = 0; i < 18; i++) {
                const mid = (lo + hi) / 2;
                if (bez(p0, p1, p2, p3, mid)[1] < y)
                    lo = mid;
                else
                    hi = mid;
            }
            return bez(p0, p1, p2, p3, (lo + hi) / 2)[0];
        };
        let x;
        if (y <= g.j1[1])
            x = solve(g.p0, g.c1, g.c2, g.j1);
        else if (y < g.j2[1])
            x = g.j1[0] + (g.j2[0] - g.j1[0]) * (y - g.j1[1]) / Math.max(1e-6, g.j2[1] - g.j1[1]);
        else
            x = solve(g.j2, g.c3, g.c4, g.fo);
        return x - g.w / 2;
    }

    // The two paths swap by opacity, never `visible`: this item is also the island's
    // content mask, inside a hidden layer, and a child re-shown under a hidden parent
    // never makes it back into the layer - the mask came back empty and so did the
    // island's content.
    Shape {
        anchors.fill: parent
        opacity: root.sculptedPath ? 1 : 0
        preferredRendererType: Shape.CurveRenderer
        antialiasing: true

        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            fillColor: root.color
            PathSvg {
                path: root.sculptedSvg
            }
        }
    }

    Shape {
        anchors.fill: parent
        opacity: root.sculptedPath ? 0 : 1
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
