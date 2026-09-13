pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

// TripleRingClock: 100% faithful replication of the 3-ring rotating concentric disc clock
// Ring 1 (Outer):  Rotating Hours (1..12) & Half-hour labels (01:30..12:30) [tangential orientation]
// Ring 2 (Middle): Rotating Minutes (00, 05..55) with radial tick cell dividers
// Ring 3 (Inner):  Rotating Seconds (00, 05..55)
// Concentric Dividers: Thin circle borders between rings
// Fixed Indicator: Horizontal pointer line starting from absolute right edge with inward arrowhead pointing to center

Canvas {
    id: root

    implicitWidth: 240
    implicitHeight: 240

    // ── Config toggles ────────────────────────────────────────────────────────
    property bool useBlackBg:            true
    property bool enableGlassReflection: false
    property bool boldFont:              true
    property string fontFamily:          Appearance.font.family.expressive || Appearance.font.family.title || "sans-serif"

    // ── Colors (WidgetColorScheme) ────────────────────────────────────────────
    property color colText:        WidgetColorScheme.textColorOnBg
    property color colSubtext:     WidgetColorScheme.subtextColorOnBg
    property color colAccent:      WidgetColorScheme.accentColor
    property color colPillFill:    WidgetColorScheme.pillFillColor
    property color colPillText:    WidgetColorScheme.textColorOnPillFill
    readonly property color tintedBgColor: WidgetColorScheme.tintBackground(
        root.useBlackBg ? Appearance.m3colors.m3shadow : WidgetColorScheme.cardBgColor)

    // ── Time ──────────────────────────────────────────────────────────────────
    property int currentHour:   DateTime.clock.hours
    property int currentMinute: DateTime.clock.minutes
    property int currentSecond: DateTime.clock.seconds

    contextType: "2d"

    Connections {
        target: DateTime.clock
        function onSecondsChanged() { root.requestPaint(); }
        function onMinutesChanged() { root.requestPaint(); }
    }

    onUseBlackBgChanged:            requestPaint()
    onBoldFontChanged:              requestPaint()
    onFontFamilyChanged:            requestPaint()
    onColTextChanged:               requestPaint()
    onColSubtextChanged:            requestPaint()
    onColAccentChanged:             requestPaint()
    onColPillFillChanged:           requestPaint()
    onTintedBgColorChanged:         requestPaint()

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();

        var W  = width;
        var cx = W / 2;
        var cy = W / 2;
        var fontStyle = boldFont ? "900 " : "700 ";
        var fFamily   = fontFamily || "sans-serif";

        var hr12 = currentHour % 12;
        var min  = currentMinute;
        var sec  = currentSecond;

        function ac(col, a) { return ColorUtils.applyAlpha(col, a); }

        // Radii for concentric discs
        var rDisk       = W * 0.485;
        var rOuter      = W * 0.395; // Ring 1: Hours & Half-hours
        var rMiddle     = W * 0.265; // Ring 2: Minutes
        var rInner      = W * 0.145; // Ring 3: Seconds

        // Progress values for continuous rotation
        var hrProgress  = (hr12 + min / 60.0 + sec / 3600.0);
        var minProgress = (min + sec / 60.0);
        var secProgress = sec;

        // ── 0. BASE CIRCULAR DISK ─────────────────────────────────────────────
        ctx.save();
        ctx.beginPath();
        ctx.arc(cx, cy, rDisk, 0, 2 * Math.PI);
        ctx.fillStyle = root.tintedBgColor;
        ctx.fill();
        ctx.restore();

        // ── CONCENTRIC RING DIVIDER CIRCLES ─────────────────────────────────
        ctx.save();
        ctx.strokeStyle = ac(colSubtext, 0.25);
        ctx.lineWidth   = 1.0;

        // Circle 1: Between Ring 1 & Ring 2
        ctx.beginPath();
        ctx.arc(cx, cy, (rOuter + rMiddle) * 0.5, 0, 2 * Math.PI);
        ctx.stroke();

        // Circle 2: Between Ring 2 & Ring 3
        ctx.beginPath();
        ctx.arc(cx, cy, (rMiddle + rInner) * 0.5, 0, 2 * Math.PI);
        ctx.stroke();
        ctx.restore();

        // ── 1. RING 1: ROTATING HOURS & HALF-HOUR LABELS (TANGENTIAL TEXT) ────
        ctx.save();
        for (var h = 1; h <= 12; h++) {
            // A) Large Hour Number (e.g. "12", "1", "2")
            var hStaticAngle = (h % 12) * (2 * Math.PI / 12);
            var hDrawAngle   = hStaticAngle - (hrProgress % 12) * (2 * Math.PI / 12);

            ctx.save();
            ctx.translate(cx, cy);
            ctx.rotate(hDrawAngle);
            ctx.translate(rOuter, 0);

            ctx.font = fontStyle + Math.round(W * 0.076) + "px '" + fFamily + "', sans-serif";
            ctx.fillStyle = colText;
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";
            ctx.fillText("" + h, 0, 0);
            ctx.restore();

            // B) Half-Hour Label (e.g. "12:30", "01:30")
            var halfStaticAngle = ((h % 12) + 0.5) * (2 * Math.PI / 12);
            var halfDrawAngle   = halfStaticAngle - (hrProgress % 12) * (2 * Math.PI / 12);
            var halfHourStr     = (h < 10 ? "0" + h : "" + h) + ":30";

            ctx.save();
            ctx.translate(cx, cy);
            ctx.rotate(halfDrawAngle);
            ctx.translate(rOuter, 0);

            ctx.font = "700 " + Math.round(W * 0.040) + "px '" + fFamily + "', sans-serif";
            ctx.fillStyle = ac(colSubtext, 0.90);
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";
            ctx.fillText(halfHourStr, 0, 0);
            ctx.restore();
        }
        ctx.restore();

        // ── 2. RING 2: ROTATING MINUTES WITH RADIAL DIVIDERS ─────────────────
        ctx.save();
        for (var m = 0; m < 12; m++) {
            var mVal = m * 5;
            var mStr = mVal < 10 ? "0" + mVal : "" + mVal;

            var mStaticAngle = m * (2 * Math.PI / 12);
            var mDrawAngle   = mStaticAngle - (minProgress / 5.0) * (2 * Math.PI / 12);

            // A) 5-Minute Step Text
            ctx.save();
            ctx.translate(cx, cy);
            ctx.rotate(mDrawAngle);
            ctx.translate(rMiddle, 0);

            ctx.font = fontStyle + Math.round(W * 0.058) + "px '" + fFamily + "', sans-serif";
            ctx.fillStyle = colText;
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";
            ctx.fillText(mStr, 0, 0);
            ctx.restore();

            // B) Radial Cell Divider Line (halfway between steps)
            var mDivAngle = (m + 0.5) * (2 * Math.PI / 12) - (minProgress / 5.0) * (2 * Math.PI / 12);
            var x1 = cx + Math.cos(mDivAngle) * (rMiddle - W * 0.035);
            var y1 = cy + Math.sin(mDivAngle) * (rMiddle - W * 0.035);
            var x2 = cx + Math.cos(mDivAngle) * (rMiddle + W * 0.035);
            var y2 = cy + Math.sin(mDivAngle) * (rMiddle + W * 0.035);

            ctx.beginPath();
            ctx.moveTo(x1, y1);
            ctx.lineTo(x2, y2);
            ctx.strokeStyle = ac(colSubtext, 0.45);
            ctx.lineWidth   = 1.3;
            ctx.stroke();
        }
        ctx.restore();

        // ── 3. RING 3: ROTATING SECONDS ──────────────────────────────────────
        ctx.save();
        for (var s = 0; s < 12; s++) {
            var sVal = s * 5;
            var sStr = sVal < 10 ? "0" + sVal : "" + sVal;

            var sStaticAngle = s * (2 * Math.PI / 12);
            var sDrawAngle   = sStaticAngle - (secProgress / 5.0) * (2 * Math.PI / 12);

            // 5-Second Step Text
            ctx.save();
            ctx.translate(cx, cy);
            ctx.rotate(sDrawAngle);
            ctx.translate(rInner, 0);

            ctx.font = (boldFont ? "800 " : "600 ") + Math.round(W * 0.048) + "px '" + fFamily + "', sans-serif";
            ctx.fillStyle = ac(colSubtext, 0.90);
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";
            ctx.fillText(sStr, 0, 0);
            ctx.restore();
        }
        ctx.restore();

        // ── 4. FIXED READOUT ARROW (ABSOLUTE RIGHT EDGE POINTER) ──────────────
        ctx.save();
        var arrowStartX = W; // Absolute right edge, zero margins
        var arrowEndX   = cx + W * 0.020;

        // Pointer horizontal line
        ctx.beginPath();
        ctx.moveTo(arrowStartX, cy);
        ctx.lineTo(arrowEndX, cy);
        ctx.strokeStyle = ac(colText, 0.95);
        ctx.lineWidth   = 2.2;
        ctx.stroke();

        // Sharp Arrowhead pointing left to center (<--)
        ctx.beginPath();
        ctx.moveTo(arrowEndX, cy);
        ctx.lineTo(arrowEndX + W * 0.035, cy - W * 0.020);
        ctx.lineTo(arrowEndX + W * 0.035, cy + W * 0.020);
        ctx.closePath();
        ctx.fillStyle = colText;
        ctx.fill();

        ctx.restore();
    }
}
