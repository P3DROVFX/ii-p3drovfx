import QtQuick
import qs.modules.ii.clock.components

/**
 * A workout's route as a line and nothing else (no map tiles): the points projected
 * equirectangularly (longitude shrunk by the cosine of the mean latitude, so a square
 * on the ground stays square), fitted to the box with the aspect kept, a dot where it
 * starts and a rounded square where it ends. `points` is the store's
 * [[epochMs, lat, lon, altM|null], …].
 */
Canvas {
    id: root

    property var points: null
    property color colLine: ClockStyle.colPrimary
    property color colStart: ClockStyle.colPrimary
    property color colOnStart: ClockStyle.colOnPrimary
    property color colEnd: ClockStyle.colTertiary
    property color colOnEnd: ClockStyle.colOnTertiary

    renderStrategy: Canvas.Cooperative

    readonly property var paintKey: [root.points, root.width, root.height, root.colLine, root.colEnd]
    onPaintKeyChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const pts = root.points ?? [];
        if (pts.length < 2)
            return;
        let lat0 = 0;
        for (const p of pts)
            lat0 += p[1];
        const k = Math.cos(lat0 / pts.length * Math.PI / 180);
        let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
        for (const p of pts) {
            const x = p[2] * k, y = -p[1];
            minX = Math.min(minX, x);
            maxX = Math.max(maxX, x);
            minY = Math.min(minY, y);
            maxY = Math.max(maxY, y);
        }
        const pad = 16;
        const scale = Math.min((width - pad * 2) / Math.max(1e-9, maxX - minX), (height - pad * 2) / Math.max(1e-9, maxY - minY));
        const ox = (width - (maxX - minX) * scale) / 2, oy = (height - (maxY - minY) * scale) / 2;
        const at = p => [ox + (p[2] * k - minX) * scale, oy + (-p[1] - minY) * scale];

        ctx.strokeStyle = root.colLine;
        ctx.lineWidth = 3;
        ctx.lineJoin = "round";
        ctx.lineCap = "round";
        ctx.beginPath();
        const first = at(pts[0]);
        ctx.moveTo(first[0], first[1]);
        for (let i = 1; i < pts.length; i++) {
            const q = at(pts[i]);
            ctx.lineTo(q[0], q[1]);
        }
        ctx.stroke();

        const end = at(pts[pts.length - 1]);
        ctx.fillStyle = root.colEnd;
        ctx.beginPath();
        ctx.roundedRect(end[0] - 7, end[1] - 7, 14, 14, 4, 4);
        ctx.fill();
        ctx.fillStyle = root.colOnEnd;
        ctx.beginPath();
        ctx.roundedRect(end[0] - 3, end[1] - 3, 6, 6, 1.5, 1.5);
        ctx.fill();

        ctx.fillStyle = root.colStart;
        ctx.beginPath();
        ctx.arc(first[0], first[1], 7, 0, Math.PI * 2);
        ctx.fill();
        ctx.fillStyle = root.colOnStart;
        ctx.beginPath();
        ctx.arc(first[0], first[1], 3, 0, Math.PI * 2);
        ctx.fill();
    }
}
