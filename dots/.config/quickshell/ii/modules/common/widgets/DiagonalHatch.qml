import QtQuick
import qs.modules.common

/**
 * Diagonal hatch texture for a rounded plate.
 *
 * Weekends need to read as "not a working day" without a second surface colour
 * competing with the today / holiday / hover / drop states a calendar cell
 * already carries, so the signal is a texture instead of a fill.
 *
 * One Canvas per cell is affordable because it repaints only when geometry,
 * colour or spacing changes -- never per frame, and never on hover.
 */
Canvas {
    id: root

    /** Stroke colour. Callers pass an already desaturated, low-alpha token. */
    property color lineColor: Appearance.colors.colTertiary
    property real lineWidth: 1
    /** Distance between two lines, measured along the x axis. */
    property real lineSpacing: 9
    /** Corner radius of the plate the lines are clipped to. */
    property real plateRadius: 0

    onLineColorChanged: requestPaint()
    onLineWidthChanged: requestPaint()
    onLineSpacingChanged: requestPaint()
    onPlateRadiusChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        if (width <= 0 || height <= 0 || lineSpacing <= 0)
            return;

        const r = Math.max(0, Math.min(plateRadius, Math.min(width, height) / 2));
        ctx.save();
        if (r > 0) {
            ctx.beginPath();
            ctx.moveTo(r, 0);
            ctx.lineTo(width - r, 0);
            ctx.arcTo(width, 0, width, r, r);
            ctx.lineTo(width, height - r);
            ctx.arcTo(width, height, width - r, height, r);
            ctx.lineTo(r, height);
            ctx.arcTo(0, height, 0, height - r, r);
            ctx.lineTo(0, r);
            ctx.arcTo(0, 0, r, 0, r);
            ctx.closePath();
            ctx.clip();
        }

        ctx.strokeStyle = lineColor;
        ctx.lineWidth = lineWidth;
        // Start a full height before the left edge so the slanted lines still
        // cover the top-left corner.
        for (let x = -height; x < width + height; x += lineSpacing) {
            ctx.beginPath();
            ctx.moveTo(x, height);
            ctx.lineTo(x + height, 0);
            ctx.stroke();
        }
        ctx.restore();
    }
}
