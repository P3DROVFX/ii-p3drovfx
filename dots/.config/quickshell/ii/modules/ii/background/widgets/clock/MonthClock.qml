pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

// MonthClock: 100% faithful circular calendar dial canvas
//   Outer ring  – Continuous Hug-Width month names. Pill width exact to text width + padding.
//   Middle ring – Day numbers 1..31 right below month names
//   Inner ring  – Weekday initials at top + dense chronograph ticks with clean symmetric margins.
//   Colors     – 100% dynamic from WidgetColorScheme

Canvas {
    id: root

    implicitWidth: 240
    implicitHeight: 240

    // ── Config toggles ────────────────────────────────────────────────────────
    property bool useBlackBg:            true
    property bool enableGlassReflection: false
    property bool showMonthRing:         true
    property bool showDayRing:           true
    property bool showWeekRing:          true
    property bool showMonthPill:         true
    property bool showDayPill:           true
    property bool showWeekPill:          true
    property bool showTickMarks:         true
    property bool boldFont:              true

    // ── Colors (WidgetColorScheme) ────────────────────────────────────────────
    property color colBg:          useBlackBg ? Appearance.m3colors.m3shadow
                                              : WidgetColorScheme.cardBgColor
    property color colText:        WidgetColorScheme.textColorOnBg
    property color colSubtext:     WidgetColorScheme.subtextColorOnBg
    property color colAccent:      WidgetColorScheme.accentColor
    property color colPillFill:    WidgetColorScheme.pillFillColor
    property color colPillText:    WidgetColorScheme.textColorOnPillFill
    property color colPillTrackTx: WidgetColorScheme.textColorOnPillTrack
    property color colInnerShape:  WidgetColorScheme.innerShapeColor
    readonly property color tintedBgColor: WidgetColorScheme.tintBackground(root.colBg)

    // ── Static data ───────────────────────────────────────────────────────────
    readonly property var fullMonthNames: [
        "JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE",
        "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"
    ]
    // S M T W T F S (Sun..Sat)
    readonly property var weekdayInitials: ["S", "M", "T", "W", "T", "F", "S"]

    contextType: "2d"

    Connections {
        target: DateTime.clock
        function onMinutesChanged() { root.requestPaint(); }
    }

    onUseBlackBgChanged:           requestPaint()
    onShowMonthRingChanged:        requestPaint()
    onShowDayRingChanged:          requestPaint()
    onShowWeekRingChanged:         requestPaint()
    onShowMonthPillChanged:        requestPaint()
    onShowDayPillChanged:          requestPaint()
    onShowWeekPillChanged:         requestPaint()
    onShowTickMarksChanged:        requestPaint()
    onBoldFontChanged:             requestPaint()
    onColBgChanged:                requestPaint()
    onTintedBgColorChanged:         requestPaint()
    onColTextChanged:              requestPaint()
    onColSubtextChanged:           requestPaint()
    onColAccentChanged:            requestPaint()
    onColPillFillChanged:          requestPaint()
    onColPillTextChanged:          requestPaint()

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();

        var W  = width;
        var cx = W / 2;
        var cy = W / 2;
        var fontStyle = "900 ";

        var now        = DateTime.clock.date;
        var todayMonth = now.getMonth();     // 0-11
        var todayDay   = now.getDate();      // 1-31
        var todayDow   = now.getDay();       // 0=Sun..6=Sat

        // ── Radii ─────────────────────────────────────────────────────────────
        var rOuterRim   = W * 0.495;
        var rMonthText  = W * 0.446; // Outer ring month text radius
        var rDayMid     = W * 0.380; // Middle ring day numbers radius
        var rWeekMid    = W * 0.315; // Inner tick ring

        function ac(col, a) { return ColorUtils.applyAlpha(col, a); }

        // ── Helper: Pill ──────────────────────────────────────────────────────
        function drawPill(px, py, angle, pw, ph, fillCol) {
            var r = ph / 2;
            ctx.save();
            ctx.translate(px, py);
            ctx.rotate(angle + Math.PI / 2);
            ctx.beginPath();
            ctx.moveTo(-pw / 2 + r, -ph / 2);
            ctx.lineTo( pw / 2 - r, -ph / 2);
            ctx.arcTo(  pw / 2, -ph / 2,  pw / 2, -ph / 2 + r, r);
            ctx.lineTo( pw / 2,  ph / 2 - r);
            ctx.arcTo(  pw / 2,  ph / 2,  pw / 2 - r, ph / 2, r);
            ctx.lineTo(-pw / 2 + r, ph / 2);
            ctx.arcTo(-pw / 2,  ph / 2, -pw / 2, ph / 2 - r, r);
            ctx.lineTo(-pw / 2, -ph / 2 + r);
            ctx.arcTo(-pw / 2, -ph / 2, -pw / 2 + r, -ph / 2, r);
            ctx.closePath();
            ctx.fillStyle = fillCol;
            ctx.fill();
            ctx.restore();
        }

        // ── 1. BACKGROUND CIRCLE ──────────────────────────────────────────────
        ctx.beginPath();
        ctx.arc(cx, cy, rOuterRim, 0, 2 * Math.PI);
        ctx.fillStyle = root.tintedBgColor;
        ctx.fill();

        // ── 2. OUTER RING: HUG-WIDTH CONTINUOUS STREAM OF MONTH NAMES ─────────
        if (showMonthRing) {
            var mFontPx = Math.round(W * 0.040);
            ctx.font = fontStyle + mFontPx + "px sans-serif";

            var spaceWidth = ctx.measureText(" ").width * 1.5;

            var monthArcs = [];
            var totalStreamPx = 0;

            for (var m = 0; m < 12; m++) {
                var name = fullMonthNames[m];
                var nameW = ctx.measureText(name).width;
                monthArcs.push({
                    name: name,
                    width: nameW,
                    spaceW: spaceWidth,
                    totalW: nameW + spaceWidth
                });
                totalStreamPx += (nameW + spaceWidth);
            }

            var scaleAngle = (2 * Math.PI) / totalStreamPx;
            var currentAngle = -Math.PI / 2;

            for (var m = 0; m < 12; m++) {
                var mData = monthArcs[m];
                var wordArc = mData.width * scaleAngle;
                var gapArc  = mData.spaceW * scaleAngle;

                var isCurM = (m === todayMonth);
                var mName  = mData.name;

                var mMidAngle = currentAngle + (wordArc / 2);

                var tx_m = cx + Math.cos(mMidAngle) * rMonthText;
                var ty_m = cy + Math.sin(mMidAngle) * rMonthText;

                // Pill width exact to text width + padding
                if (showMonthPill && isCurM) {
                    var pw = mData.width + (W * 0.048);
                    drawPill(tx_m, ty_m, mMidAngle, pw, W * 0.058, colPillFill);
                }

                var mCol = isCurM ? colPillText : ac(colText, 0.96);

                var charArc = currentAngle;
                ctx.font = fontStyle + mFontPx + "px sans-serif";
                ctx.fillStyle = mCol;
                ctx.textAlign = "center";
                ctx.textBaseline = "middle";

                for (var ch = 0; ch < mName.length; ch++) {
                    var cW = ctx.measureText(mName[ch]).width * scaleAngle;
                    var cAngle = charArc + (cW / 2);

                    var cX = cx + Math.cos(cAngle) * rMonthText;
                    var cY = cy + Math.sin(cAngle) * rMonthText;

                    var rot = cAngle + Math.PI / 2;
                    if (cAngle > Math.PI / 2 || cAngle < -Math.PI / 2) {
                        if (rot > Math.PI)  rot -= Math.PI * 2;
                        if (rot < -Math.PI) rot += Math.PI * 2;
                    }

                    ctx.save();
                    ctx.translate(cX, cY);
                    ctx.rotate(rot);
                    ctx.fillText(mName[ch], 0, 0);
                    ctx.restore();

                    charArc += cW;
                }

                currentAngle += (wordArc + gapArc);
            }
        }

        // ── 3. MIDDLE RING: DAY NUMBERS (1..31) ───────────────────────────────
        if (showDayRing) {
            var dim    = new Date(now.getFullYear(), todayMonth + 1, 0).getDate();
            var dStep  = (2 * Math.PI) / dim;
            var dStart = -Math.PI / 2;

            for (var d = 1; d <= dim; d++) {
                var dAngle = dStart + (d - 1) * dStep;
                var isCurD = (d === todayDay);
                var tx_d   = cx + Math.cos(dAngle) * rDayMid;
                var ty_d   = cy + Math.sin(dAngle) * rDayMid;

                if (showDayPill && isCurD) {
                    drawPill(tx_d, ty_d, dAngle, W * 0.064, W * 0.050, colPillFill);
                }

                var dCol = isCurD ? colPillText : ac(colText, 0.96);

                var dRot = dAngle + Math.PI / 2;
                if (dAngle > Math.PI / 2 || dAngle < -Math.PI / 2) {
                    if (dRot > Math.PI)  dRot -= Math.PI * 2;
                    if (dRot < -Math.PI) dRot += Math.PI * 2;
                }

                ctx.save();
                ctx.translate(tx_d, ty_d);
                ctx.rotate(dRot);
                ctx.font = fontStyle + Math.round(W * 0.036) + "px sans-serif";
                ctx.textAlign = "center";
                ctx.textBaseline = "middle";
                ctx.fillStyle = dCol;
                ctx.fillText("" + d, 0, 0);
                ctx.restore();
            }
        }

        // ── 4. INNER RING: WEEKDAY INITIALS (TOP) + DENSE TICKS ──────────────
        if (showWeekRing) {
            // Symmetrical top arc (-PI*0.70 to -PI*0.30)
            var wStartAngle = -Math.PI * 0.70;
            var wEndAngle   = -Math.PI * 0.30;
            var wStep       = (wEndAngle - wStartAngle) / 6;

            for (var w = 0; w < 7; w++) {
                var wAngle = wStartAngle + w * wStep;
                var isCurW = (w === todayDow);
                var tx_w   = cx + Math.cos(wAngle) * rWeekMid;
                var ty_w   = cy + Math.sin(wAngle) * rWeekMid;

                if (showWeekPill && isCurW) {
                    drawPill(tx_w, ty_w, wAngle, W * 0.052, W * 0.046, colPillFill);
                }

                var wCol = isCurW ? colPillText : ac(colText, 0.96);

                var wRot = wAngle + Math.PI / 2;
                if (wAngle > Math.PI / 2 || wAngle < -Math.PI / 2) {
                    if (wRot > Math.PI)  wRot -= Math.PI * 2;
                    if (wRot < -Math.PI) wRot += Math.PI * 2;
                }

                ctx.save();
                ctx.translate(tx_w, ty_w);
                ctx.rotate(wRot);
                ctx.font = fontStyle + Math.round(W * 0.036) + "px sans-serif";
                ctx.textAlign = "center";
                ctx.textBaseline = "middle";
                ctx.fillStyle = wCol;
                ctx.fillText(weekdayInitials[w], 0, 0);
                ctx.restore();
            }

            // ── DENSE CHRONOGRAPH TICKS (Clean symmetrical margin around weekdays)
            if (showTickMarks) {
                ctx.save();
                var totalTicks = 120;
                // Protection margin around weekday arc
                var protectMargin = 0.22;

                for (var i = 0; i < totalTicks; i++) {
                    var tAngle = -Math.PI / 2 + (i * 2 * Math.PI / totalTicks);

                    // Skip top arc where weekdays are rendered (symmetrical check)
                    if (tAngle >= wStartAngle - protectMargin && tAngle <= wEndAngle + protectMargin)
                        continue;

                    var isMajor = (i % 10 === 0);
                    var isMedium= (i % 5 === 0);
                    var tLen    = isMajor ? W * 0.026 : isMedium ? W * 0.018 : W * 0.010;
                    var tWidth  = isMajor ? 2.0 : isMedium ? 1.4 : 1.0;
                    var r1      = rWeekMid - tLen / 2;
                    var r2      = rWeekMid + tLen / 2;

                    ctx.lineWidth   = tWidth;
                    ctx.strokeStyle = ac(colSubtext, isMajor ? 0.75 : isMedium ? 0.50 : 0.28);
                    ctx.beginPath();
                    ctx.moveTo(cx + Math.cos(tAngle) * r1, cy + Math.sin(tAngle) * r1);
                    ctx.lineTo(cx + Math.cos(tAngle) * r2, cy + Math.sin(tAngle) * r2);
                    ctx.stroke();
                }
                ctx.restore();
            }
        }
    }
}
