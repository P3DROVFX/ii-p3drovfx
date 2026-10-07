.pragma library

// Turning a sequence of pointer samples into something worth looking at.
//
// A stylus reports at whatever rate the driver manages, and a finger reports jitter it
// never meant. Drawing the raw samples gives a line that is simultaneously too angular
// (samples too far apart on a fast stroke) and too wobbly (samples too close together
// on a slow one). The three passes here are what stands between that and ink:
//
//   thin      — drop samples closer than a pixel or two, so a stationary finger stops
//               adding points and the smoothing pass has something to work with;
//   smooth    — exponential filter on position, which is what takes the tremble out;
//   widths    — pressure into line width, with a floor, so a light stroke is thin and
//               not invisible.
//
// The rendering itself lives in the canvas, but the arithmetic lives here so it can be
// checked without a tablet, a compositor or a stylus.

/// A point is { x, y, p } — p being pressure in 0..1.
function point(x, y, pressure) {
    return {
        x: Number(x) || 0,
        y: Number(y) || 0,
        p: clamp(pressure === undefined || pressure === null ? 1 : Number(pressure), 0, 1)
    };
}

function clamp(value, low, high) {
    var number = Number(value);
    if (!isFinite(number))
        return low;
    return Math.max(low, Math.min(high, number));
}

function distance(a, b) {
    var dx = a.x - b.x;
    var dy = a.y - b.y;
    return Math.sqrt(dx * dx + dy * dy);
}

/**
 * Whether a new sample is far enough from the last to be worth keeping.
 *
 * Without this a finger resting on the glass adds hundreds of coincident points, every
 * one of which is a segment the canvas draws — the ink darkens under a stationary
 * finger, and the smoothing below has nothing but noise to average.
 */
function shouldAppend(last, candidate, minimumDistance) {
    if (!last)
        return true;
    var threshold = minimumDistance === undefined ? 1.6 : minimumDistance;
    return distance(last, candidate) >= threshold;
}

/**
 * One exponential smoothing step towards a new sample.
 *
 * `strength` is 0..1, where 0 is the raw sample and 1 never moves. Applied to position
 * only: smoothing pressure as well makes a deliberate press feel like it is lagging,
 * and pressure noise is not what anyone sees.
 */
function smoothed(previous, sample, strength) {
    if (!previous)
        return sample;
    var alpha = clamp(strength, 0, 0.95);
    return point(previous.x + (sample.x - previous.x) * (1 - alpha),
                 previous.y + (sample.y - previous.y) * (1 - alpha),
                 sample.p);
}

/**
 * The width to stroke a segment with.
 *
 * The floor is the important part. Mapping pressure straight onto width means the
 * beginning and end of every stroke — where pressure ramps through zero — are drawn at
 * zero width, so strokes appear to start late and stop early. A third of the nominal
 * width at zero pressure keeps the ends visible while leaving most of the range to the
 * pen.
 */
function widthFor(baseWidth, pressure, usePressure) {
    var base = Math.max(0.5, Number(baseWidth) || 1);
    if (!usePressure)
        return base;
    return base * (0.34 + 0.66 * clamp(pressure, 0, 1));
}

/**
 * The control point and end point for one smoothed segment.
 *
 * The classic midpoint trick: the sample itself becomes a quadratic control point and
 * the curve ends halfway to the next sample. Consecutive curves then meet with
 * matching tangents, so a polyline of hard corners becomes one continuous line without
 * needing to fit anything.
 */
function quadraticSegment(from, through, to) {
    return {
        controlX: through.x,
        controlY: through.y,
        endX: to ? (through.x + to.x) / 2 : through.x,
        endY: to ? (through.y + to.y) / 2 : through.y,
        // Averaged so the width of a segment matches the ink either side of it rather
        // than stepping at every sample.
        pressure: to ? (through.p + to.p) / 2 : through.p
    };
}

/// The bounding box of a set of strokes, padded, or null when there is no ink.
///
/// Used to crop what gets saved: a note holding a full-screen PNG that is 98% empty is
/// a note nobody can read at a glance.
function boundsOf(strokes, padding) {
    var pad = padding === undefined ? 24 : padding;
    var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    var list = strokes || [];
    for (var i = 0; i < list.length; ++i) {
        var points = list[i] ? hitPoints(list[i]) : [];
        var half = (list[i] ? drawnWidth(list[i]) : 1) / 2 + 1;
        for (var j = 0; j < points.length; ++j) {
            minX = Math.min(minX, points[j].x - half);
            minY = Math.min(minY, points[j].y - half);
            maxX = Math.max(maxX, points[j].x + half);
            maxY = Math.max(maxY, points[j].y + half);
        }
    }
    if (!isFinite(minX))
        return null;
    return {
        x: minX - pad,
        y: minY - pad,
        width: (maxX - minX) + pad * 2,
        height: (maxY - minY) + pad * 2
    };
}

/// Whether a stroke passes close enough to a point to be rubbed out by it.
///
/// Whole strokes, not pixels: an eraser that takes bites out of a line leaves fragments
/// nobody wanted, and on a device with no undo shortcut the forgiving behaviour is the
/// one that removes what you were aiming at.
function strokeHitBy(stroke, x, y, radius) {
    var points = stroke ? hitPoints(stroke) : [];
    var reach = (radius === undefined ? 18 : radius) + (stroke ? drawnWidth(stroke) : 0) / 2;
    for (var i = 0; i < points.length; ++i) {
        var dx = points[i].x - x;
        var dy = points[i].y - y;
        if (dx * dx + dy * dy <= reach * reach)
            return true;
    }
    return false;
}

/// Whether a stroke's width varies along it. A mouse or a finger reports pressure 1 on
/// every sample, so even with pressure switched on their strokes are drawn as one
/// even-width path; only a measuring device needs the outline below.
function isVariable(stroke) {
    if (!stroke || !stroke.usePressure || !isFreehand(stroke) || toolOf(stroke) === "highlighter")
        return false;
    var points = stroke.points || [];
    for (var i = 0; i < points.length; ++i) {
        if (points[i].p < 0.999)
            return true;
    }
    return false;
}

/**
 * The midpoint-quadratic curve of `quadraticSegment`, as a dense polyline.
 *
 * Both renderers draw this same list: the canvas that holds the finished ink and the
 * vector shape that draws the stroke under the pen. Drawing the same geometry is what
 * keeps a stroke from shifting by a pixel at the moment it is committed. Each curve is
 * cut into steps of about four pixels, which is below what the eye resolves at the
 * widths a pen draws.
 */
function flattened(points) {
    var list = points || [];
    if (list.length < 3)
        return list.slice();

    var out = [list[0]];
    var fromX = (list[0].x + list[1].x) / 2;
    var fromY = (list[0].y + list[1].y) / 2;
    out.push({ x: fromX, y: fromY, p: (list[0].p + list[1].p) / 2 });

    for (var i = 1; i < list.length; ++i) {
        var segment = quadraticSegment(list[i - 1], list[i], i + 1 < list.length ? list[i + 1] : null);
        var length = Math.abs(segment.controlX - fromX) + Math.abs(segment.controlY - fromY)
            + Math.abs(segment.endX - segment.controlX) + Math.abs(segment.endY - segment.controlY);
        var steps = Math.max(1, Math.min(8, Math.ceil(length / 4)));
        var startP = out[out.length - 1].p;
        for (var s = 1; s <= steps; ++s) {
            var t = s / steps;
            var u = 1 - t;
            out.push({
                x: u * u * fromX + 2 * u * t * segment.controlX + t * t * segment.endX,
                y: u * u * fromY + 2 * u * t * segment.controlY + t * t * segment.endY,
                p: startP + (segment.pressure - startP) * t
            });
        }
        fromX = segment.endX;
        fromY = segment.endY;
    }
    return out;
}

function _arc(out, cx, cy, radius, from, to, steps) {
    for (var s = 1; s < steps; ++s) {
        var angle = from + (to - from) * (s / steps);
        out.push({ x: cx + Math.cos(angle) * radius, y: cy + Math.sin(angle) * radius });
    }
}

/**
 * The outline of a stroke whose width changes along it, as one closed polygon.
 *
 * A path can only be stroked at one width, so a pressure stroke is drawn as the area it
 * covers instead: each sample pushed out to either side along its normal by half its
 * width, the two sides joined by round caps. Filled with the non-zero rule, so where the
 * stroke crosses itself the overlap stays filled.
 */
function outline(flat, baseWidth, usePressure) {
    var list = flat || [];
    var out = [];
    if (list.length === 0)
        return out;

    if (list.length === 1) {
        var r = widthFor(baseWidth, list[0].p, usePressure) / 2;
        _arc(out, list[0].x, list[0].y, r, 0, Math.PI * 2, 17);
        return out;
    }

    var left = [];
    var right = [];
    var angles = [];
    for (var i = 0; i < list.length; ++i) {
        var a = list[Math.max(0, i - 1)];
        var b = list[Math.min(list.length - 1, i + 1)];
        var tx = b.x - a.x;
        var ty = b.y - a.y;
        var length = Math.sqrt(tx * tx + ty * ty);
        var angle = length > 0.0001 ? Math.atan2(ty, tx) : (angles.length > 0 ? angles[angles.length - 1] : 0);
        angles.push(angle);
        var half = widthFor(baseWidth, list[i].p, usePressure) / 2;
        var nx = -Math.sin(angle) * half;
        var ny = Math.cos(angle) * half;
        left.push({ x: list[i].x + nx, y: list[i].y + ny });
        right.push({ x: list[i].x - nx, y: list[i].y - ny });
    }

    var last = list.length - 1;
    for (i = 0; i <= last; ++i)
        out.push(left[i]);
    _arc(out, list[last].x, list[last].y, widthFor(baseWidth, list[last].p, usePressure) / 2,
         angles[last] + Math.PI / 2, angles[last] - Math.PI / 2, 8);
    for (i = last; i >= 0; --i)
        out.push(right[i]);
    _arc(out, list[0].x, list[0].y, widthFor(baseWidth, list[0].p, usePressure) / 2,
         angles[0] - Math.PI / 2, angles[0] - Math.PI * 1.5, 8);
    return out;
}

function _n(value) {
    return Math.round(value * 10) / 10;
}

/**
 * An even-width stroke as SVG path data: the midpoint-quadratic curves themselves, which
 * a vector renderer draws natively. A single sample becomes a hair-long line, so the
 * round caps have something to stand on and the tap draws as a dot.
 */
function curveSvg(points) {
    var list = points || [];
    if (list.length === 0)
        return "";
    if (list.length === 1)
        return "M" + _n(list[0].x) + " " + _n(list[0].y) + "L" + _n(list[0].x + 0.05) + " " + _n(list[0].y);
    if (list.length === 2)
        return "M" + _n(list[0].x) + " " + _n(list[0].y) + "L" + _n(list[1].x) + " " + _n(list[1].y);

    var parts = ["M", _n(list[0].x), " ", _n(list[0].y),
                 "L", _n((list[0].x + list[1].x) / 2), " ", _n((list[0].y + list[1].y) / 2)];
    for (var i = 1; i < list.length; ++i) {
        var segment = quadraticSegment(list[i - 1], list[i], i + 1 < list.length ? list[i + 1] : null);
        parts.push("Q", _n(segment.controlX), " ", _n(segment.controlY), " ", _n(segment.endX), " ", _n(segment.endY));
    }
    return parts.join("");
}

/// A closed polygon (see `outline`) as SVG path data.
function outlineSvg(polygon) {
    var list = polygon || [];
    if (list.length === 0)
        return "";
    var parts = ["M", _n(list[0].x), " ", _n(list[0].y)];
    for (var i = 1; i < list.length; ++i)
        parts.push("L", _n(list[i].x), " ", _n(list[i].y));
    parts.push("Z");
    return parts.join("");
}

/**
 * The lazy brush: where the ink goes when the pointer pulls a string of `length` from
 * the brush. Null while the string is slack (the pointer is still within reach), so a
 * hand trembling in place moves nothing; otherwise the brush is dragged along the line
 * to the pointer until it is exactly `length` behind it. Pressure is the pointer's.
 */
function pulled(brush, pointer, length) {
    if (!brush)
        return pointer;
    var dx = pointer.x - brush.x;
    var dy = pointer.y - brush.y;
    var d = Math.sqrt(dx * dx + dy * dy);
    if (d <= length)
        return null;
    var k = (d - length) / d;
    return point(brush.x + dx * k, brush.y + dy * k, pointer.p);
}

// ── Tools ──────────────────────────────────────────────────────────────────
//
// A stroke is { tool, points, color, width, usePressure }. `tool` is absent on strokes
// drawn before tools existed, and those are pen strokes.
//
//   pen          freehand, pressure-aware
//   highlighter  freehand, wide and translucent, painted under the ink
//   line, arrow  two points: where the drag started and where it ended
//   rect, ellipse  two points: opposite corners of the box
//
// The laser never becomes a stroke: it is drawn, it fades, it is gone.

var SHAPES = ["line", "arrow", "rect", "ellipse"];

function toolOf(stroke) {
    return stroke && stroke.tool ? stroke.tool : "pen";
}

function isShape(stroke) {
    return SHAPES.indexOf(toolOf(stroke)) >= 0;
}

function isFreehand(stroke) {
    return !isShape(stroke);
}

/// A highlighter is a marker: three times the pen's width, never thinner than 12 px.
function drawnWidth(stroke) {
    var width = Math.max(0.5, Number(stroke && stroke.width) || 1);
    return toolOf(stroke) === "highlighter" ? Math.max(12, width * 3) : width;
}

/// How opaque a stroke is painted. Highlighter ink lets the text under it show.
function alphaOf(stroke) {
    return toolOf(stroke) === "highlighter" ? 0.38 : 1;
}

/**
 * The end point of a shape drag, constrained while Shift is held: lines and arrows snap
 * to 15° steps, boxes become squares and circles.
 */
function constrained(tool, start, end) {
    var dx = end.x - start.x;
    var dy = end.y - start.y;
    if (tool === "line" || tool === "arrow") {
        var length = Math.sqrt(dx * dx + dy * dy);
        var step = Math.PI / 12;
        var angle = Math.round(Math.atan2(dy, dx) / step) * step;
        return point(start.x + Math.cos(angle) * length, start.y + Math.sin(angle) * length, end.p);
    }
    var side = Math.max(Math.abs(dx), Math.abs(dy));
    return point(start.x + (dx < 0 ? -side : side), start.y + (dy < 0 ? -side : side), end.p);
}

/**
 * A shape as the polylines that draw it: each a list of points stroked with round caps
 * and joins. The arrowhead is two short strokes from the tip, sized from the line width
 * so a thick arrow keeps a head in proportion.
 */
function shapePolylines(stroke) {
    var pts = stroke && stroke.points ? stroke.points : [];
    if (pts.length === 0)
        return [];
    var a = pts[0];
    var b = pts[pts.length - 1];
    var tool = toolOf(stroke);

    if (tool === "line")
        return [[a, b]];

    if (tool === "arrow") {
        var dx = b.x - a.x, dy = b.y - a.y;
        var length = Math.sqrt(dx * dx + dy * dy);
        if (length < 0.5)
            return [[a, b]];
        var head = Math.min(length * 0.5, Math.max(14, drawnWidth(stroke) * 4));
        var angle = Math.atan2(dy, dx);
        var spread = Math.PI / 7;
        var left = { x: b.x - Math.cos(angle - spread) * head, y: b.y - Math.sin(angle - spread) * head };
        var right = { x: b.x - Math.cos(angle + spread) * head, y: b.y - Math.sin(angle + spread) * head };
        return [[a, b], [left, b, right]];
    }

    var x0 = Math.min(a.x, b.x), x1 = Math.max(a.x, b.x);
    var y0 = Math.min(a.y, b.y), y1 = Math.max(a.y, b.y);
    if (tool === "rect")
        return [[{ x: x0, y: y0 }, { x: x1, y: y0 }, { x: x1, y: y1 }, { x: x0, y: y1 }, { x: x0, y: y0 }]];

    // ellipse
    var cx = (x0 + x1) / 2, cy = (y0 + y1) / 2, rx = (x1 - x0) / 2, ry = (y1 - y0) / 2;
    var ring = [];
    var steps = Math.max(24, Math.min(96, Math.round((rx + ry) / 4)));
    for (var i = 0; i <= steps; ++i) {
        var t = (i / steps) * Math.PI * 2;
        ring.push({ x: cx + Math.cos(t) * rx, y: cy + Math.sin(t) * ry });
    }
    return [ring];
}

/// Points along whatever a stroke draws, close enough together for the eraser and the
/// crop to treat as the stroke itself.
function hitPoints(stroke) {
    if (!isShape(stroke))
        return stroke && stroke.points ? stroke.points : [];
    var out = [];
    var lines = shapePolylines(stroke);
    for (var l = 0; l < lines.length; ++l) {
        var line = lines[l];
        for (var i = 0; i < line.length; ++i) {
            out.push(line[i]);
            if (i + 1 < line.length) {
                var d = distance(line[i], line[i + 1]);
                var n = Math.floor(d / 8);
                for (var k = 1; k < n; ++k)
                    out.push({ x: line[i].x + (line[i + 1].x - line[i].x) * k / n,
                               y: line[i].y + (line[i + 1].y - line[i].y) * k / n });
            }
        }
    }
    return out;
}

function polylinesSvg(lines) {
    var parts = [];
    for (var l = 0; l < lines.length; ++l) {
        var line = lines[l];
        if (line.length === 0)
            continue;
        parts.push("M", _n(line[0].x), " ", _n(line[0].y));
        for (var i = 1; i < line.length; ++i)
            parts.push("L", _n(line[i].x), " ", _n(line[i].y));
    }
    return parts.join("");
}

/// SVG path data for any stroke: what the live shape draws, and what an export writes.
/// `filled` is true when the path is an outline to fill rather than a line to stroke.
function strokeSvg(stroke) {
    if (isShape(stroke))
        return { d: polylinesSvg(shapePolylines(stroke)), filled: false };
    var points = stroke && stroke.points ? stroke.points : [];
    if (isVariable(stroke))
        return { d: outlineSvg(outline(flattened(points), stroke.width, stroke.usePressure)), filled: true };
    return { d: curveSvg(points), filled: false };
}

function _escape(value) {
    return String(value).replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;");
}

/**
 * A whole sheet as an SVG document, cropped to the ink with `padding` around it.
 * Highlighter strokes go first, so they sit under the ink as they do on screen.
 */
function documentSvg(strokes, padding) {
    var bounds = boundsOf(strokes, padding === undefined ? 24 : padding);
    if (!bounds)
        return "";
    var ordered = (strokes || []).filter(function (s) { return toolOf(s) === "highlighter"; })
        .concat((strokes || []).filter(function (s) { return toolOf(s) !== "highlighter"; }));
    var body = [];
    for (var i = 0; i < ordered.length; ++i) {
        var stroke = ordered[i];
        var svg = strokeSvg(stroke);
        if (!svg.d)
            continue;
        var opacity = alphaOf(stroke) < 1 ? ' opacity="' + alphaOf(stroke) + '"' : "";
        if (svg.filled)
            body.push('  <path d="' + svg.d + '" fill="' + _escape(stroke.color) + '"' + opacity + '/>');
        else
            body.push('  <path d="' + svg.d + '" fill="none" stroke="' + _escape(stroke.color) + '" stroke-width="'
                      + _n(drawnWidth(stroke)) + '" stroke-linecap="round" stroke-linejoin="round"' + opacity + '/>');
    }
    return '<svg xmlns="http://www.w3.org/2000/svg" width="' + Math.ceil(bounds.width) + '" height="' + Math.ceil(bounds.height)
        + '" viewBox="' + _n(bounds.x) + ' ' + _n(bounds.y) + ' ' + _n(bounds.width) + ' ' + _n(bounds.height) + '">\n'
        + body.join("\n") + '\n</svg>\n';
}
