.pragma library

// Where a ray from the centre of a rounded square meets its edge.
// Dials that follow the outline of a squircle (tick rings, numerals hugging a
// rectangular screen) place their marks with this instead of a circle radius.
//   angleDeg  clockwise from 12 o'clock
//   half      half the side of the square the marks live on
//   radius    corner radius of that square (0..half)
// Returns the distance from the centre along the ray.
function distance(angleDeg, half, radius) {
    const a = angleDeg * Math.PI / 180;
    const dx = Math.sin(a);
    const dy = -Math.cos(a);
    const r = Math.max(0, Math.min(radius, half));
    const t = half / Math.max(Math.abs(dx), Math.abs(dy));
    const px = dx * t;
    const py = dy * t;
    const inner = half - r;
    if (Math.abs(px) <= inner || Math.abs(py) <= inner)
        return t;
    // The square's corner was hit: intersect the corner arc instead.
    const cx = Math.sign(px) * inner;
    const cy = Math.sign(py) * inner;
    const dot = dx * cx + dy * cy;
    const disc = dot * dot - (cx * cx + cy * cy) + r * r;
    return dot + Math.sqrt(Math.max(0, disc));
}

function point(angleDeg, half, radius, centre) {
    const d = distance(angleDeg, half, radius);
    const a = angleDeg * Math.PI / 180;
    return Qt.point(centre + Math.sin(a) * d, centre - Math.cos(a) * d);
}
