import QtQuick
import QtQuick.Shapes

/**
 * Launcher-icon mask in the style of a given phone vendor. Android hands the
 * launcher a square adaptive icon and lets the OEM cut it to taste; this
 * reproduces those cuts with the same corner model Lawnchair uses (one cubic
 * Bézier per corner, a per-corner size, and measured control-point constants
 * for Samsung's One UI and Apple's iOS). The AOSP shapes match the platform's
 * own config_icon_mask paths exactly. Meant as an OpacityMask source: the
 * filled area is what shows.
 */
Shape {
    id: root

    // One of the keys in AndroidIconMask.shapes
    property string shapeName: "oneui"
    property color fillColor: "black"

    // Control-point distance from the corner, as a fraction of the corner box.
    // 0.4478 is the classic circular-arc approximation; smaller hugs the corner.
    readonly property real arcDistance: 0.44777152

    // corners: [topLeft, topRight, bottomRight, bottomLeft]; each is
    // { kind: "arc" | "bezier" | "cupertino", dx, dy, sx, sy } where d* are the
    // control distances and s* the corner size relative to half the icon.
    readonly property var shapes: ({
        "circle":        root._uniform("arc", root.arcDistance, root.arcDistance, 1, 1),
        "oneui":         root._uniform("bezier", 0.4431717, 0.14010102, 1, 1),
        "ios":           root._uniform("cupertino", 0, 0, 1, 1),
        "squircle":      root._uniform("bezier", 0.2, 0.2, 1, 1),
        "roundedSquare": root._uniform("arc", root.arcDistance, root.arcDistance, 0.6, 0.6),
        "square":        root._uniform("arc", root.arcDistance, root.arcDistance, 0.16, 0.16),
        "sharpSquare":   root._uniform("arc", root.arcDistance, root.arcDistance, 0, 0),
        "cylinder":      root._uniform("arc", root.arcDistance, root.arcDistance, 1, 0.6),
        "teardrop":      [
            root._corner("arc", root.arcDistance, root.arcDistance, 1, 1),
            root._corner("arc", root.arcDistance, root.arcDistance, 1, 1),
            root._corner("arc", root.arcDistance, root.arcDistance, 0.3, 0.3),
            root._corner("arc", root.arcDistance, root.arcDistance, 1, 1)
        ]
    })

    preferredRendererType: Shape.CurveRenderer
    antialiasing: true

    function _corner(kind: string, dx: real, dy: real, sx: real, sy: real): var {
        return { kind, dx, dy, sx, sy };
    }

    function _uniform(kind: string, dx: real, dy: real, sx: real, sy: real): var {
        const c = root._corner(kind, dx, dy, sx, sy);
        return [c, c, c, c];
    }

    // Each corner in its own unit box: where the curve starts, the box corner
    // it bends around, and where it ends. Same orientation as Lawnchair.
    readonly property var _positions: ({
        "topLeft":     { sx: 0, sy: 1, cx: 0, cy: 0, ex: 1, ey: 0 },
        "topRight":    { sx: 0, sy: 0, cx: 1, cy: 0, ex: 1, ey: 1 },
        "bottomRight": { sx: 1, sy: 0, cx: 1, cy: 1, ex: 0, ey: 1 },
        "bottomLeft":  { sx: 1, sy: 1, cx: 0, cy: 1, ex: 0, ey: 0 }
    })

    // iOS's continuous corner, sampled by Lawnchair as three cubics.
    readonly property var _cupertinoScales: {
        const half = [[0.302716, 0], [0.5035, 0], [0.603866, 0], [0.71195, 0.0341666], [0.82995, 0.0771166]];
        return half.concat(half.slice().reverse().map(p => [p[1], p[0]]));
    }

    function _lerp(t: real, a: real, b: real): real {
        return a + t * (b - a);
    }

    function _pt(x: real, y: real): string {
        return x.toFixed(3) + "," + y.toFixed(3);
    }

    function _cornerPath(name: string, corner: var, w: real, h: real, ox: real, oy: real): string {
        const p = root._positions[name];
        const end = root._pt(ox + p.ex * w, oy + p.ey * h);
        if (w <= 0 || h <= 0) return "L" + end;

        if (corner.kind === "cupertino") {
            const reversed = (name === "topLeft" || name === "bottomRight");
            const scales = reversed ? root._cupertinoScales.slice().reverse() : root._cupertinoScales;
            const pts = scales.map((s, i) => {
                const fwd = i < 5;
                const x = root._lerp(s[0], fwd ? p.sx : p.ex, fwd ? p.ex : p.sx);
                const y = root._lerp(s[1], fwd ? p.sy : p.ey, fwd ? p.ey : p.sy);
                return root._pt(ox + x * w, oy + y * h);
            });
            let d = "L" + pts[0];
            for (let i = 1; i <= 7; i += 3) d += "C" + pts[i] + " " + pts[i + 1] + " " + pts[i + 2];
            return d + "L" + end;
        }

        const c1 = root._pt(ox + root._lerp(corner.dx, p.cx, p.sx) * w, oy + root._lerp(corner.dy, p.cy, p.sy) * h);
        const c2 = root._pt(ox + root._lerp(corner.dx, p.cx, p.ex) * w, oy + root._lerp(corner.dy, p.cy, p.ey) * h);
        return "C" + c1 + " " + c2 + " " + end;
    }

    function _pathFor(name: string, width: real, height: real): string {
        const corners = root.shapes[name] ?? root.shapes["circle"];
        const size = Math.min(width, height);
        const half = size / 2;
        const left = (width - size) / 2, top = (height - size) / 2;
        const right = left + size, bottom = top + size;
        const [tl, tr, br, bl] = corners;

        // Bottom-right → bottom-left → top-left → top-right, like Lawnchair.
        let d = "M" + root._pt(right, bottom - br.sy * half);
        d += root._cornerPath("bottomRight", br, br.sx * half, br.sy * half, right - br.sx * half, bottom - br.sy * half);
        d += "L" + root._pt(left + bl.sx * half, bottom);
        d += root._cornerPath("bottomLeft", bl, bl.sx * half, bl.sy * half, left, bottom - bl.sy * half);
        d += "L" + root._pt(left, top + tl.sy * half);
        d += root._cornerPath("topLeft", tl, tl.sx * half, tl.sy * half, left, top);
        d += "L" + root._pt(right - tr.sx * half, top);
        d += root._cornerPath("topRight", tr, tr.sx * half, tr.sy * half, right - tr.sx * half, top);
        return d + "Z";
    }

    ShapePath {
        strokeWidth: -1
        fillColor: root.fillColor

        PathSvg {
            path: root._pathFor(root.shapeName, root.width, root.height)
        }
    }
}
