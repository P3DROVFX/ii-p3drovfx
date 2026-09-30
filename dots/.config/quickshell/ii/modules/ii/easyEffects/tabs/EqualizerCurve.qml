pragma ComponentBehavior: Bound

import QtQuick

import qs.modules.common
import qs.modules.common.functions
import qs.modules.ii.clock.components
import "../../../../services/easyEffects/EasyEffectsLogic.js" as Logic

/**
 * The equalizer's summed response, 20 Hz to 20 kHz: the shape of the preset at a glance.
 *
 * Painted once per change of the bands and never otherwise, so an open editor costs no
 * frames while nothing moves. With split channels the second channel is drawn too, in
 * the tertiary colour. `highlightBand` marks one band's frequency.
 */
Canvas {
    id: root

    /// The equalizer block (with its channel sections).
    property var block: null
    property var channels: ["left", "right"]
    property int highlightBand: -1
    property string highlightChannel: ""

    readonly property int bandCount: Number(root.block?.["num-bands"] ?? 0)
    readonly property bool split: root.block?.["split-channels"] === true
    readonly property var frequencies: Logic.logFrequencies(160, 20, 20000)
    readonly property var primary: Logic.equalizerResponse(root.block?.[root.channels[0]], root.bandCount, root.frequencies)
    readonly property var secondary: root.split ? Logic.equalizerResponse(root.block?.[root.channels[1]], root.bandCount, root.frequencies) : []
    readonly property real range: {
        let peak = 6;
        root.primary.concat(root.secondary).forEach(v => peak = Math.max(peak, Math.abs(v)));
        return Math.min(36, Math.ceil((peak + 3) / 6) * 6);
    }

    readonly property color colLine: Appearance.colors.colPrimary
    readonly property color colLine2: Appearance.colors.colTertiary
    readonly property color colGrid: ColorUtils.applyAlpha(Appearance.colors.colOnSurfaceVariant, 0.16)
    readonly property color colLabel: ColorUtils.applyAlpha(Appearance.colors.colOnSurfaceVariant, 0.7)

    implicitHeight: 150
    onPrimaryChanged: root.requestPaint()
    onSecondaryChanged: root.requestPaint()
    onHighlightBandChanged: root.requestPaint()
    onColLineChanged: root.requestPaint()
    onWidthChanged: root.requestPaint()
    onHeightChanged: root.requestPaint()

    function xFor(f: real): real {
        return (Math.log10(f) - Math.log10(20)) / (Math.log10(20000) - Math.log10(20)) * root.width;
    }

    function yFor(db: real): real {
        const pad = 10;
        return pad + (1 - (db + root.range) / (2 * root.range)) * (root.height - pad * 2);
    }

    function trace(ctx: var, values: var, color: color, fill: bool): void {
        if (values.length === 0)
            return;
        ctx.beginPath();
        for (let i = 0; i < values.length; i++) {
            const x = root.xFor(root.frequencies[i]);
            const y = root.yFor(Math.max(-root.range, Math.min(root.range, values[i])));
            if (i === 0)
                ctx.moveTo(x, y);
            else
                ctx.lineTo(x, y);
        }
        ctx.lineWidth = 2.5;
        ctx.strokeStyle = color;
        ctx.stroke();
        if (!fill)
            return;
        ctx.lineTo(root.width, root.yFor(0));
        ctx.lineTo(0, root.yFor(0));
        ctx.closePath();
        ctx.fillStyle = ColorUtils.applyAlpha(color, 0.14);
        ctx.fill();
    }

    onPaint: {
        const ctx = root.getContext("2d");
        ctx.reset();
        ctx.font = `${Appearance.font.pixelSize.smallest}px "${ClockStyle.fontMain}"`;

        // Decades and the level lines.
        ctx.lineWidth = 1;
        ctx.strokeStyle = root.colGrid;
        [50, 100, 200, 500, 1000, 2000, 5000, 10000].forEach(f => {
            const x = Math.round(root.xFor(f)) + 0.5;
            ctx.beginPath();
            ctx.moveTo(x, 0);
            ctx.lineTo(x, root.height);
            ctx.stroke();
        });
        [-root.range / 2, 0, root.range / 2].forEach(db => {
            const y = Math.round(root.yFor(db)) + 0.5;
            ctx.beginPath();
            ctx.moveTo(0, y);
            ctx.lineTo(root.width, y);
            ctx.stroke();
        });
        ctx.fillStyle = root.colLabel;
        [[100, "100"], [1000, "1k"], [10000, "10k"]].forEach(pair => ctx.fillText(pair[1], root.xFor(pair[0]) + 4, root.height - 4));
        ctx.fillText(`+${root.range / 2} dB`, 4, root.yFor(root.range / 2) - 3);
        ctx.fillText(`−${root.range / 2}`, 4, root.yFor(-root.range / 2) - 3);

        if (root.highlightBand >= 0) {
            const band = root.block?.[root.highlightChannel || root.channels[0]]?.[`band${root.highlightBand}`];
            if (band) {
                const x = root.xFor(Math.max(20, Math.min(20000, Number(band.frequency) || 1000)));
                ctx.fillStyle = ColorUtils.applyAlpha(root.colLine, 0.18);
                ctx.fillRect(x - 3, 0, 6, root.height);
            }
        }

        root.trace(ctx, root.secondary, root.colLine2, false);
        root.trace(ctx, root.primary, root.colLine, true);
    }
}
