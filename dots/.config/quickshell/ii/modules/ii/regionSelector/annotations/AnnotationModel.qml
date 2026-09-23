pragma Singleton
import QtQuick
import Quickshell

// Pure helper library for the inline region-editor annotation object model.
// Annotations are plain dicts of the shape:
//   { id, type, z, geom: {...}, style: { stroke, strokeWidth, fill, fillOpacity, opacity, fontPx } }
// Geometry keys per type:
//   rect    -> { x, y, w, h }
//   arrow   -> { x1, y1, x2, y2 }
//   ruler   -> { x1, y1, x2, y2 } (measured segment; fixed tuner styling)
//   circle  -> { x, y, r }
//   star    -> { x, y, outerR, innerR }
//   pencil  -> { points: [{x, y}, ...] }
//   blur    -> { points: [{x, y}, ...] }
//   (line = arrow; circle/number = {x, y, r}; text = rect + text;
//    highlighter/gaussblur = pencil)
Singleton {
    id: model

    function defaultStyle(color, lineWidth) {
        return {
            "stroke": String(color),
            "strokeWidth": lineWidth,
            "fill": null,
            "fillOpacity": 0.4,
            "opacity": 1,
            "fontPx": 20
        };
    }

    function make(type, id, z, geom, style) {
        return {
            "id": id,
            "type": type,
            "z": z,
            "geom": geom,
            "style": style
        };
    }

    function clone(ann) {
        return JSON.parse(JSON.stringify(ann));
    }

    // Deep copy of the whole scene, safe to push onto the undo/redo stacks.
    // Normalises the QML list<var> into a JS array first (Array.isArray fails on list<var>).
    function snapshot(anns) {
        var arr = Array.from(anns);
        var out = [];
        for (var i = 0; i < arr.length; i++) out.push(clone(arr[i]))
        return out;
    }

    function boundingBox(ann) {
        var g = ann.geom ?? ann;
        switch (ann.type) {
        case "rect":
            return {
                "x": g.x ?? 0,
                "y": g.y ?? 0,
                "w": g.w ?? g.width ?? 0,
                "h": g.h ?? g.height ?? 0
            };
        case "circle":
            {
                var r = g.r ?? g.radius ?? 0;
                return {
                    "x": (g.x ?? 0) - r,
                    "y": (g.y ?? 0) - r,
                    "w": r * 2,
                    "h": r * 2
                };
            };
        case "star":
            {
                var o = g.outerR ?? g.outerRadius ?? 0;
                return {
                    "x": (g.x ?? 0) - o,
                    "y": (g.y ?? 0) - o,
                    "w": o * 2,
                    "h": o * 2
                };
            };
        case "number":
            {
                var br = g.r ?? 16;
                return {
                    "x": (g.x ?? 0) - br,
                    "y": (g.y ?? 0) - br,
                    "w": br * 2,
                    "h": br * 2
                };
            };
        case "text":
            return {
                "x": g.x ?? 0,
                "y": g.y ?? 0,
                "w": g.w ?? 0,
                "h": g.h ?? 0
            };
        case "arrow":
        case "line":
        case "ruler":
            return {
                "x": Math.min(g.x1 ?? 0, g.x2 ?? 0),
                "y": Math.min(g.y1 ?? 0, g.y2 ?? 0),
                "w": Math.abs((g.x2 ?? 0) - (g.x1 ?? 0)),
                "h": Math.abs((g.y2 ?? 0) - (g.y1 ?? 0))
            };
        case "pencil":
        case "blur":
        case "gaussblur":
        case "highlighter":
            {
                var pts = g.points ?? [];
                if (pts.length === 0)
                    return {
                    "x": 0,
                    "y": 0,
                    "w": 0,
                    "h": 0
                };

                var minX = pts[0].x, minY = pts[0].y, maxX = pts[0].x, maxY = pts[0].y;
                for (var i = 1; i < pts.length; i++) {
                    minX = Math.min(minX, pts[i].x);
                    minY = Math.min(minY, pts[i].y);
                    maxX = Math.max(maxX, pts[i].x);
                    maxY = Math.max(maxY, pts[i].y);
                }
                return {
                    "x": minX,
                    "y": minY,
                    "w": maxX - minX,
                    "h": maxY - minY
                };
            };
        }
        return {
            "x": 0,
            "y": 0,
            "w": 0,
            "h": 0
        };
    }

    // Point-inside test against the (padded) bounding box. Padding gives thin
    // shapes (lines, pencil strokes) a grabbable margin.
    function contains(ann, px, py, tol) {
        var t = tol ?? 6;
        var b = boundingBox(ann);
        return px >= b.x - t && px <= b.x + b.w + t && py >= b.y - t && py <= b.y + b.h + t;
    }

    // Topmost annotation (highest z) whose box contains the point, or null.
    function annotationAt(anns, px, py, tol) {
        var arr = Array.from(anns);
        arr.sort(function(a, b) {
            return (b.z ?? 0) - (a.z ?? 0);
        });
        for (var i = 0; i < arr.length; i++) {
            if (contains(arr[i], px, py, tol))
                return arr[i];

        }
        return null;
    }

    // Shift an annotation's geometry by (dx, dy) in place; returns it.
    function translate(ann, dx, dy) {
        var g = ann.geom;
        switch (ann.type) {
        case "rect":
        case "circle":
        case "star":
        case "text":
        case "number":
            g.x += dx;
            g.y += dy;
            break;
        case "arrow":
        case "line":
        case "ruler":
            g.x1 += dx;
            g.y1 += dy;
            g.x2 += dx;
            g.y2 += dy;
            break;
        case "pencil":
        case "blur":
        case "gaussblur":
        case "highlighter":
            for (var p = 0; p < g.points.length; p++) {
                g.points[p].x += dx;
                g.points[p].y += dy;
            }
            break;
        }
        return ann;
    }

    // Resize grips. (ax, ay) is the grip's normalised spot on the bounding
    // box and l/t/r/b say which edges it drags; p1/p2 are line endpoints.
    readonly property var gripSlots: [
        { "id": "tl", "ax": 0, "ay": 0, "l": true, "t": true, "r": false, "b": false, "edge": false },
        { "id": "tr", "ax": 1, "ay": 0, "l": false, "t": true, "r": true, "b": false, "edge": false },
        { "id": "bl", "ax": 0, "ay": 1, "l": true, "t": false, "r": false, "b": true, "edge": false },
        { "id": "br", "ax": 1, "ay": 1, "l": false, "t": false, "r": true, "b": true, "edge": false },
        { "id": "t", "ax": 0.5, "ay": 0, "l": false, "t": true, "r": false, "b": false, "edge": true },
        { "id": "b", "ax": 0.5, "ay": 1, "l": false, "t": false, "r": false, "b": true, "edge": true },
        { "id": "l", "ax": 0, "ay": 0.5, "l": true, "t": false, "r": false, "b": false, "edge": true },
        { "id": "r", "ax": 1, "ay": 0.5, "l": false, "t": false, "r": true, "b": false, "edge": true },
        { "id": "p1" },
        { "id": "p2" }
    ]
    readonly property real minGripSize: 6

    // Round shapes, badges and text scale uniformly, so they only get corners.
    function lockedAspect(type) {
        return type === "circle" || type === "star" || type === "number" || type === "text";
    }

    // Where a grip sits for this annotation (editor-local), or null when the
    // annotation doesn't use it. Box grips sit on the bounding box grown by
    // `pad`, matching the selection outline.
    function gripPosition(ann, slot, pad) {
        if (!ann || !slot)
            return null;
        var g = ann.geom;
        var endpoints = ann.type === "arrow" || ann.type === "line" || ann.type === "ruler";
        if (slot.id === "p1")
            return endpoints ? { "x": g.x1, "y": g.y1 } : null;
        if (slot.id === "p2")
            return endpoints ? { "x": g.x2, "y": g.y2 } : null;
        if (endpoints || (slot.edge && lockedAspect(ann.type)))
            return null;
        var b = boundingBox(ann);
        var p = pad ?? 0;
        return {
            "x": b.x - p + (b.w + p * 2) * slot.ax,
            "y": b.y - p + (b.h + p * 2) * slot.ay
        };
    }

    // `start` after dragging grip `slot` by (dx, dy). Always computed from the
    // drag's starting copy so motion events don't compound rounding.
    function resized(start, slot, dx, dy) {
        var ann = clone(start);
        var g = ann.geom;
        if (slot.id === "p1" || slot.id === "p2") {
            g[slot.id === "p1" ? "x1" : "x2"] += dx;
            g[slot.id === "p1" ? "y1" : "y2"] += dy;
            return ann;
        }
        var b = boundingBox(start);
        var m = minGripSize;
        var x1 = b.x, y1 = b.y, x2 = b.x + b.w, y2 = b.y + b.h;
        if (slot.l)
            x1 = Math.min(x1 + dx, x2 - m);
        if (slot.r)
            x2 = Math.max(x2 + dx, x1 + m);
        if (slot.t)
            y1 = Math.min(y1 + dy, y2 - m);
        if (slot.b)
            y2 = Math.max(y2 + dy, y1 + m);
        if (lockedAspect(start.type) && b.w > 0 && b.h > 0) {
            // Follow whichever axis moved further, anchored on the opposite corner.
            var k = Math.max((x2 - x1) / b.w, (y2 - y1) / b.h);
            if (slot.l)
                x1 = x2 - b.w * k;
            else
                x2 = x1 + b.w * k;
            if (slot.t)
                y1 = y2 - b.h * k;
            else
                y2 = y1 + b.h * k;
        }
        var w = x2 - x1, h = y2 - y1;
        switch (start.type) {
        case "rect":
            g.x = x1;
            g.y = y1;
            g.w = w;
            g.h = h;
            break;
        case "circle":
        case "number":
            g.r = w / 2;
            g.x = x1 + w / 2;
            g.y = y1 + h / 2;
            break;
        case "star":
            {
                var outer = start.geom.outerR ?? start.geom.outerRadius ?? 0;
                var inner = start.geom.innerR ?? start.geom.innerRadius ?? 0;
                g.outerR = w / 2;
                g.innerR = outer > 0 ? inner * (w / 2) / outer : w / 4;
                g.x = x1 + w / 2;
                g.y = y1 + h / 2;
                break;
            };
        case "text":
            g.x = x1;
            g.y = y1;
            g.w = w;
            g.h = h;
            ann.style.fontPx = Math.max(6, Math.round((start.style.fontPx ?? 20) * h / b.h));
            break;
        case "pencil":
        case "blur":
        case "gaussblur":
        case "highlighter":
            {
                // A perfectly straight stroke has no extent on one axis;
                // centre it in the new box instead of dividing by zero.
                var pts = g.points;
                for (var i = 0; i < pts.length; i++) {
                    pts[i].x = b.w > 0 ? x1 + (pts[i].x - b.x) * w / b.w : x1 + w / 2;
                    pts[i].y = b.h > 0 ? y1 + (pts[i].y - b.y) * h / b.h : y1 + h / 2;
                }
                break;
            };
        }
        return ann;
    }

}
