pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.ii.clock.components

/**
 * A card's 30-day trend: one value per day, oldest first, `null` for a day without
 * data (a gap, not a zero). A line with a soft fill, its last point marked; bars
 * instead for counts, where most days are zero.
 */
Canvas {
    id: root

    property var values: []
    property color color: ClockStyle.colPrimary
    /// Counts (resets, kills) read better as bars than as a line.
    property bool bars: false
    /// The scale's floor and ceiling; by default the values' own range.
    property real minValue: NaN
    property real maxValue: NaN

    implicitHeight: 36
    renderStrategy: Canvas.Cooperative

    onValuesChanged: requestPaint()
    onColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const vals = Array.from(root.values ?? []);
        const known = vals.filter(v => v !== null && v !== undefined && !isNaN(v));
        if (known.length === 0)
            return;
        const lo = isNaN(root.minValue) ? Math.min(...known) : root.minValue;
        const hi = isNaN(root.maxValue) ? Math.max(...known) : root.maxValue;
        const span = Math.max(1e-6, hi - lo);
        const w = width, h = height, n = vals.length;
        const step = w / Math.max(1, n);
        const y = v => h - 3 - (h - 6) * Math.min(1, Math.max(0, (v - lo) / span));
        if (root.bars) {
            ctx.fillStyle = root.color;
            for (let i = 0; i < n; i++) {
                const v = vals[i];
                if (v === null || v === undefined || !(v > 0))
                    continue;
                const top = y(v);
                ctx.fillRect(i * step + step * 0.2, top, step * 0.6, h - top);
            }
            return;
        }
        ctx.strokeStyle = root.color;
        ctx.lineWidth = 2;
        ctx.lineJoin = "round";
        let last = null;
        let open = false;
        ctx.beginPath();
        for (let i = 0; i < n; i++) {
            const v = vals[i];
            if (v === null || v === undefined || isNaN(v)) {
                open = false;
                continue;
            }
            const px = i * step + step / 2, py = y(v);
            if (open)
                ctx.lineTo(px, py);
            else
                ctx.moveTo(px, py);
            open = true;
            last = [px, py];
        }
        ctx.stroke();
        if (last) {
            ctx.fillStyle = root.color;
            ctx.beginPath();
            ctx.arc(last[0], last[1], 3, 0, Math.PI * 2);
            ctx.fill();
        }
    }
}
