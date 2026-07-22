pragma Singleton
import QtQuick
import Quickshell

// Pure helper library for the inline region-editor annotation object model.
// Annotations are plain dicts of the shape:
//   { id, type, z, geom: {...}, style: { stroke, strokeWidth, fill, fillOpacity, opacity, fontPx } }
// Geometry keys per type:
//   rect    -> { x, y, w, h }
//   arrow   -> { x1, y1, x2, y2 }
//   circle  -> { x, y, r }
//   star    -> { x, y, outerR, innerR }
//   pencil  -> { points: [{x, y}, ...] }
//   blur    -> { points: [{x, y}, ...] }
Singleton {
    id: model

    function defaultStyle(color, lineWidth) {
        return {
            "stroke": String(color),
            "strokeWidth": lineWidth,
            "fill": null,
            "fillOpacity": 0.25,
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
        case "arrow":
            return {
                "x": Math.min(g.x1 ?? 0, g.x2 ?? 0),
                "y": Math.min(g.y1 ?? 0, g.y2 ?? 0),
                "w": Math.abs((g.x2 ?? 0) - (g.x1 ?? 0)),
                "h": Math.abs((g.y2 ?? 0) - (g.y1 ?? 0))
            };
        case "pencil":
        case "blur":
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

}
