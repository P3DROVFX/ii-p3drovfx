.pragma library

// How one screen frames its wallpaper - zoom, position, orientation - as
// arithmetic.
//
// Pure for the same reason `widget_align.js` is: nothing about the rendered
// wallpaper plane is reachable from qmltestrunner, and the part worth checking
// is exactly the part that can go wrong on screen: whether the picture still
// covers the plane it is drawn into. The wallpaper surface sizes and places one
// Item from `layout()`; Edit Mode's overlay turns a drag, a wheel step or a
// button into a new framing through the other functions here.
//
// A framing is `{ zoom, x, y, rotation, flipH, flipV }`:
//   zoom      1 = the picture just covers the plane (the cover fit every
//             wallpaper already gets); never below it, because the lock
//             screen's zoom-out lands on exactly that fit and anything smaller
//             would show the plane's edges through it.
//   x, y      where the picture sits inside the room the zoom leaves, -1..1 per
//             axis on the SCREEN's axes: -1 shows the left (top) edge, 0 is
//             centred, 1 the right (bottom) edge. Relative rather than in
//             pixels, so the same framing stays valid at every scale the plane
//             is drawn at (workspace zoom, the lock, the overview) and can
//             never ask for more room than there is.
//   rotation  0, 90, 180 or 270, clockwise.
//   flipH/V   mirrored horizontally / vertically.
//
// `layout()` also takes a continuous angle, which is what makes a quarter turn
// animatable: half-way through, a rectangle that covered the plane square-on
// no longer covers its corners, so the picture is scaled up just enough to keep
// covering them (coverCorrection) and the plane never shows through.

var ZOOM_MIN = 1.0;
var ZOOM_MAX = 4.0;
var EPSILON = 0.0005;

function defaults() {
    return { "zoom": 1, "x": 0, "y": 0, "rotation": 0, "flipH": false, "flipV": false };
}

function clamp(value, lo, hi) {
    return Math.max(lo, Math.min(hi, value));
}

function finite(value, fallback) {
    const n = Number(value);
    return isFinite(n) ? n : fallback;
}

// A quarter turn, from anything: -90, 450, 89.9 and "180" all land on one of
// the four orientations.
function snapRotation(value) {
    const quarters = Math.round(finite(value, 0) / 90);
    return ((quarters % 4) + 4) % 4 * 90;
}

// Whatever the config held, as a framing that is safe to draw: a hand-edited
// file, a value from an older build, NaN from a bad division upstream.
function normalize(raw) {
    const source = raw ?? {};
    return {
        "zoom": clamp(finite(source.zoom, 1), ZOOM_MIN, ZOOM_MAX),
        "x": clamp(finite(source.x, 0), -1, 1),
        "y": clamp(finite(source.y, 0), -1, 1),
        "rotation": snapRotation(source.rotation),
        "flipH": source.flipH === true,
        "flipV": source.flipV === true
    };
}

function isIdentity(raw) {
    const f = normalize(raw);
    return Math.abs(f.zoom - 1) < EPSILON
        && Math.abs(f.x) < EPSILON
        && Math.abs(f.y) < EPSILON
        && f.rotation === 0
        && !f.flipH
        && !f.flipV;
}

function equal(a, b) {
    const p = normalize(a);
    const q = normalize(b);
    return Math.abs(p.zoom - q.zoom) < EPSILON
        && Math.abs(p.x - q.x) < EPSILON
        && Math.abs(p.y - q.y) < EPSILON
        && p.rotation === q.rotation
        && p.flipH === q.flipH
        && p.flipV === q.flipV;
}

// Whether a quarter turn swaps the picture's width and height on screen.
function isSideways(rotation) {
    return snapRotation(rotation) % 180 !== 0;
}

// The axis-aligned box a w x h rectangle occupies once turned by `angle`.
function rotatedBounds(width, height, angle) {
    const radians = angle * Math.PI / 180;
    const c = Math.abs(Math.cos(radians));
    const s = Math.abs(Math.sin(radians));
    return { "width": width * c + height * s, "height": width * s + height * c };
}

// The smallest factor (>= 1) a rectangle of `width` x `height`, centred at
// (cx, cy) from the plane's centre and turned clockwise by `angle`, has to be
// scaled by about its own centre so it covers every corner of a
// planeWidth x planeHeight plane. Exactly 1 for a square-on rectangle that
// already covers - the common case - and above it only in the middle of an
// animated turn.
function coverCorrection(planeWidth, planeHeight, width, height, angle, cx, cy) {
    if (!(width > 0) || !(height > 0))
        return 1;
    const radians = angle * Math.PI / 180;
    const c = Math.cos(radians);
    const s = Math.sin(radians);
    let k = 1;
    for (const sx of [-1, 1]) {
        for (const sy of [-1, 1]) {
            const px = sx * planeWidth / 2 - cx;
            const py = sy * planeHeight / 2 - cy;
            // Into the rectangle's own frame: the inverse of a clockwise turn
            // on y-down coordinates.
            const u = px * c + py * s;
            const v = -px * s + py * c;
            k = Math.max(k, 2 * Math.abs(u) / width, 2 * Math.abs(v) / height);
        }
    }
    // Round-off on a square-on rectangle sitting exactly on its bound would
    // otherwise come back as 1.0000000002 and zoom a hair on every frame.
    return k - 1 < 1e-9 ? 1 : k;
}

// Where the picture goes inside a planeWidth x planeHeight plane.
//
// Returns the Item to draw the picture into, in the plane's coordinates:
//   width, height   the UNturned picture at its drawn size (the image's own
//                   aspect ratio - turning happens on the Item)
//   x, y            the picture's centre, from the plane's centre
//   angle           clockwise degrees to turn it by
//   scaleX, scaleY  -1 where mirrored
//   rangeX, rangeY  the room the pan has on each axis, in plane pixels: how
//                   far the centre may sit from the plane's centre
//   scale           drawn size / the image's own pixel size
//
// `angle` overrides the framing's own rotation, for the frames of an animated
// turn; leave it undefined otherwise.
function layout(planeWidth, planeHeight, imageWidth, imageHeight, raw, angle) {
    const f = normalize(raw);
    const turn = angle === undefined || angle === null ? f.rotation : finite(angle, f.rotation);
    const result = {
        "width": planeWidth,
        "height": planeHeight,
        "x": 0,
        "y": 0,
        "angle": 0,
        "scaleX": 1,
        "scaleY": 1,
        "rangeX": 0,
        "rangeY": 0,
        "scale": 1
    };
    if (!(planeWidth > 0) || !(planeHeight > 0) || !(imageWidth > 0) || !(imageHeight > 0))
        return result;

    const bounds = rotatedBounds(imageWidth, imageHeight, turn);
    const cover = Math.max(planeWidth / bounds.width, planeHeight / bounds.height);
    let scale = cover * f.zoom;
    const rangeX = Math.max(0, (bounds.width * scale - planeWidth) / 2);
    const rangeY = Math.max(0, (bounds.height * scale - planeHeight) / 2);
    const cx = -f.x * rangeX;
    const cy = -f.y * rangeY;
    scale *= coverCorrection(planeWidth, planeHeight, imageWidth * scale, imageHeight * scale, turn, cx, cy);

    result.width = imageWidth * scale;
    result.height = imageHeight * scale;
    result.x = cx;
    result.y = cy;
    result.angle = turn;
    result.scaleX = f.flipH ? -1 : 1;
    result.scaleY = f.flipV ? -1 : 1;
    result.rangeX = rangeX;
    result.rangeY = rangeY;
    result.scale = scale;
    return result;
}

// The position for a pointer that has moved (dx, dy) plane pixels since the
// press, from the framing held at the press: dragging right brings the left
// of the picture into view. An axis with no room keeps its value - there is
// nothing to move, and zeroing it would lose the position a later zoom-in
// gives room back to.
//
// `snap` (plane pixels) pulls an axis onto a target when the picture's centre
// comes within that distance of it. `targets` lists them per axis as offsets
// of the picture's centre from the plane's centre - `{ x: [..], y: [..] }`;
// left out, the one target is the centre itself (0). `snappedX/Y` say whether
// an axis snapped and `snapIndexX/Y` to which target (-1 when none), so the
// overlay can draw that guide.
function snapAxis(value, range, threshold, targets) {
    let best = -1;
    let bestDistance = Infinity;
    const centre = -value * range;
    for (let i = 0; i < targets.length; i++) {
        const target = finite(targets[i], NaN);
        if (!isFinite(target) || Math.abs(target) > range + EPSILON)
            continue;
        const distance = Math.abs(centre - target);
        if (distance <= threshold && distance < bestDistance) {
            best = i;
            bestDistance = distance;
        }
    }
    if (best < 0)
        return { "value": value, "index": -1 };
    return { "value": clamp(-targets[best] / range, -1, 1), "index": best };
}

function panTo(start, dx, dy, rangeX, rangeY, snap, targets) {
    const f = normalize(start);
    const threshold = Math.max(0, finite(snap, 0));
    const targetsX = Array.isArray(targets?.x) ? targets.x : [0];
    const targetsY = Array.isArray(targets?.y) ? targets.y : [0];
    let x = f.x;
    let y = f.y;
    let snapIndexX = -1;
    let snapIndexY = -1;
    if (rangeX > EPSILON) {
        x = clamp(f.x - dx / rangeX, -1, 1);
        if (threshold > 0) {
            const hit = snapAxis(x, rangeX, threshold, targetsX);
            x = hit.value;
            snapIndexX = hit.index;
        }
    }
    if (rangeY > EPSILON) {
        y = clamp(f.y - dy / rangeY, -1, 1);
        if (threshold > 0) {
            const hit = snapAxis(y, rangeY, threshold, targetsY);
            y = hit.value;
            snapIndexY = hit.index;
        }
    }
    return {
        "x": x,
        "y": y,
        "snappedX": snapIndexX >= 0,
        "snappedY": snapIndexY >= 0,
        "snapIndexX": snapIndexX,
        "snapIndexY": snapIndexY,
        // Which walls the drag is pressing against, for the edge glow.
        "atLeft": rangeX > EPSILON && x <= -1 + EPSILON,
        "atRight": rangeX > EPSILON && x >= 1 - EPSILON,
        "atTop": rangeY > EPSILON && y <= -1 + EPSILON,
        "atBottom": rangeY > EPSILON && y >= 1 - EPSILON
    };
}

// Where a point of the picture - (u, v) in the picture's own coordinates,
// 0..1 from its top-left - lands from the picture's centre, in plane pixels,
// for a `layout()` result: turned first, then mirrored on the screen's axes,
// the order the wallpaper surface applies them in.
function pointOffset(frame, u, v) {
    const px = (finite(u, 0.5) - 0.5) * frame.width;
    const py = (finite(v, 0.5) - 0.5) * frame.height;
    const radians = finite(frame.angle, 0) * Math.PI / 180;
    const c = Math.cos(radians);
    const s = Math.sin(radians);
    return {
        "x": (px * c - py * s) * (frame.scaleX < 0 ? -1 : 1),
        "y": (px * s + py * c) * (frame.scaleY < 0 ? -1 : 1)
    };
}

// A new zoom that keeps the point under the pointer where it is - as far as
// the new room allows. (px, py) is the pointer from the plane's centre.
function zoomAt(planeWidth, planeHeight, imageWidth, imageHeight, raw, zoom, px, py) {
    const f = normalize(raw);
    const nextZoom = clamp(finite(zoom, f.zoom), ZOOM_MIN, ZOOM_MAX);
    const before = layout(planeWidth, planeHeight, imageWidth, imageHeight, f);
    const centred = Object.assign({}, f, { "zoom": nextZoom, "x": 0, "y": 0 });
    const after = layout(planeWidth, planeHeight, imageWidth, imageHeight, centred);
    const next = Object.assign({}, f, { "zoom": nextZoom });
    if (!(before.scale > 0) || !(after.scale > 0))
        return next;
    const ratio = after.scale / before.scale;
    const pointerX = finite(px, 0);
    const pointerY = finite(py, 0);
    const cx = pointerX - (pointerX - before.x) * ratio;
    const cy = pointerY - (pointerY - before.y) * ratio;
    next.x = after.rangeX > EPSILON ? clamp(-cx / after.rangeX, -1, 1) : 0;
    next.y = after.rangeY > EPSILON ? clamp(-cy / after.rangeY, -1, 1) : 0;
    return next;
}

// A quarter turn (`turns` = 1 clockwise, -1 counter-clockwise) that keeps the
// part of the picture at the centre of the screen at the centre: the
// picture's offset turns with it.
function rotateBy(planeWidth, planeHeight, imageWidth, imageHeight, raw, turns) {
    const f = normalize(raw);
    const step = Math.round(finite(turns, 0));
    const next = Object.assign({}, f, { "rotation": snapRotation(f.rotation + step * 90) });
    if (step === 0)
        return next;
    const before = layout(planeWidth, planeHeight, imageWidth, imageHeight, f);
    const after = layout(planeWidth, planeHeight, imageWidth, imageHeight,
        Object.assign({}, next, { "x": 0, "y": 0 }));
    const quarter = ((step % 4) + 4) % 4;
    let cx = before.x;
    let cy = before.y;
    for (let i = 0; i < quarter; i++) {
        const turned = -cy;
        cy = cx;
        cx = turned;
    }
    next.x = after.rangeX > EPSILON ? clamp(-cx / after.rangeX, -1, 1) : 0;
    next.y = after.rangeY > EPSILON ? clamp(-cy / after.rangeY, -1, 1) : 0;
    return next;
}

// A mirror that keeps the centre of the screen on the same part of the
// picture: the offset mirrors with it.
function flip(raw, axis) {
    const f = normalize(raw);
    if (axis === "horizontal")
        return Object.assign({}, f, { "flipH": !f.flipH, "x": f.x === 0 ? 0 : -f.x });
    if (axis === "vertical")
        return Object.assign({}, f, { "flipV": !f.flipV, "y": f.y === 0 ? 0 : -f.y });
    return f;
}

// The shortest way from one orientation to the next, as a continuous angle
// for the animation: 270 -> 0 turns forward to 360, not back through 180.
function animationTarget(fromAngle, toRotation) {
    const from = finite(fromAngle, 0);
    const to = snapRotation(toRotation);
    let delta = ((to - from) % 360 + 540) % 360 - 180;
    return from + delta;
}
