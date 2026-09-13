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
        var points = list[i] && list[i].points ? list[i].points : [];
        var half = (list[i] && list[i].width ? list[i].width : 1) / 2 + 1;
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
    var points = stroke && stroke.points ? stroke.points : [];
    var reach = (radius === undefined ? 18 : radius) + (stroke && stroke.width ? stroke.width : 0) / 2;
    for (var i = 0; i < points.length; ++i) {
        var dx = points[i].x - x;
        var dy = points[i].y - y;
        if (dx * dx + dy * dy <= reach * reach)
            return true;
    }
    return false;
}
