pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The last 30 days from the helper's daily summaries (`history`): one stacked column
 * per day — failed units, crashes, new journal errors — and one line across them,
 * root disk use or the memory-pressure peak, picked with the chips.
 *
 * A day the helper did not run is left blank rather than drawn as a zero, so a quiet
 * week and a week without data do not look alike. The caption compares this week
 * with the one before; hovering a day reads that day out instead.
 */
Rectangle {
    id: root

    readonly property int dayCount: 30
    /// "disk" | "memory"
    property string series: "disk"
    property int hovered: -1

    // Error and tertiary sit too close in most palettes to tell apart as stacked
    // bars; the least severe part of the stack is the quietest.
    readonly property color colFailed: ClockStyle.colError
    readonly property color colCrashes: ClockStyle.colPrimary
    readonly property color colErrors: Qt.rgba(ClockStyle.colOnSurface.r, ClockStyle.colOnSurface.g, ClockStyle.colOnSurface.b, 0.3)
    readonly property color colLine: ClockStyle.colTertiary
    readonly property color colGuide: ClockStyle.colOnSurface

    /// dayCount slots, oldest first: { date, row } where row is null for a day with no data.
    readonly property var days: {
        const byDate = {};
        for (const d of Array.from(HealthService.history ?? []))
            byDate[d.date] = d;
        const out = [];
        const today = new Date();
        for (let i = root.dayCount - 1; i >= 0; i--) {
            const d = new Date(today.getFullYear(), today.getMonth(), today.getDate() - i);
            const key = Qt.formatDate(d, "yyyy-MM-dd");
            out.push({ date: d, row: byDate[key] ?? null });
        }
        return out;
    }
    readonly property bool hasData: root.days.some(d => d.row !== null)
    readonly property real maxStack: Math.max(1, ...root.days.map(d => d.row ? Number(d.row.failed ?? 0) + Number(d.row.crashes ?? 0) + Number(d.row.newErrors ?? 0) : 0))
    /// The history field the line draws. A day's bootMs is 0 when it did not boot.
    readonly property string lineField: root.series === "disk" ? "diskPct" : root.series === "boot" ? "bootMs" : "psiMemPeak"
    readonly property real maxLine: root.series === "disk" ? 100 : Math.max(1, ...root.days.map(d => Number(d.row?.[root.lineField] ?? 0)))

    function sum(from, to, field): int {
        let n = 0;
        for (let i = from; i < to; i++)
            n += Number(root.days[i]?.row?.[field] ?? 0);
        return n;
    }

    readonly property string caption: {
        if (!root.hasData)
            return Translation.tr("Filled in day by day while the checks run.");
        if (root.hovered >= 0) {
            const d = root.days[root.hovered];
            const day = Qt.formatDate(d.date, "ddd d MMM");
            if (!d.row)
                return Translation.tr("%1 · no data").arg(day);
            const parts = [day,
                HealthText.plural(d.row.failed ?? 0, Translation.tr("%1 failed unit"), Translation.tr("%1 failed units")),
                HealthText.plural(d.row.crashes ?? 0, Translation.tr("%1 crash"), Translation.tr("%1 crashes")),
                HealthText.plural(d.row.newErrors ?? 0, Translation.tr("%1 new error"), Translation.tr("%1 new errors"))];
            parts.push(root.series === "disk" ? Translation.tr("disk %1 %").arg(Math.round(Number(d.row.diskPct ?? 0)))
                : root.series === "boot" ? (Number(d.row.bootMs ?? 0) > 0 ? Translation.tr("booted in %1").arg(HealthText.seconds(d.row.bootMs)) : Translation.tr("no boot"))
                : Translation.tr("memory stalled %1 %").arg(Number(d.row.psiMemPeak ?? 0).toFixed(1)));
            return parts.join(" · ");
        }
        const n = root.dayCount;
        const now = ["crashes", "failed", "newErrors"].map(f => root.sum(n - 7, n, f));
        const before = ["crashes", "failed", "newErrors"].map(f => root.sum(n - 14, n - 7, f));
        return Translation.tr("This week: %1 · %2 · %3. The week before: %4 crashes, %5 failed, %6 new errors.")
            .arg(HealthText.plural(now[0], Translation.tr("%1 crash"), Translation.tr("%1 crashes")))
            .arg(HealthText.plural(now[1], Translation.tr("%1 failed unit"), Translation.tr("%1 failed units")))
            .arg(HealthText.plural(now[2], Translation.tr("%1 new error"), Translation.tr("%1 new errors")))
            .arg(before[0]).arg(before[1]).arg(before[2]);
    }

    implicitHeight: column.implicitHeight + ClockStyle.gapLarge * 2
    radius: ClockStyle.radiusLarge
    color: ClockStyle.colPane

    onDaysChanged: canvas.requestPaint()
    onSeriesChanged: canvas.requestPaint()
    onHoveredChanged: canvas.requestPaint()

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: ClockStyle.gapLarge
        }
        spacing: ClockStyle.gapSmall

        RowLayout {
            Layout.fillWidth: true
            spacing: ClockStyle.gapSmall

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Last 30 days")
                font.pixelSize: ClockStyle.textSmall - 1
                font.weight: Font.Black
                font.letterSpacing: 0.8
                font.capitalization: Font.AllUppercase
                color: ClockStyle.colSubtext
            }

            ClockChip {
                symbol: "hard_drive"
                label: Translation.tr("Disk")
                selected: root.series === "disk"
                onClicked: root.series = "disk"
            }
            ClockChip {
                symbol: "memory"
                label: Translation.tr("Memory")
                selected: root.series === "memory"
                onClicked: root.series = "memory"
            }
            ClockChip {
                symbol: "timer"
                label: Translation.tr("Boot")
                selected: root.series === "boot"
                onClicked: root.series = "boot"
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 120

            Canvas {
                id: canvas
                anchors.fill: parent
                renderStrategy: Canvas.Cooperative

                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const w = width, h = height;
                    const n = root.dayCount;
                    const slot = w / n;
                    const barW = Math.max(2, slot * 0.58);
                    const base = h - 2;
                    const top = 6;
                    const scale = (base - top) / root.maxStack;

                    // Faint guides at a half and the top of the bar scale.
                    ctx.strokeStyle = Qt.rgba(root.colGuide.r, root.colGuide.g, root.colGuide.b, 0.08);
                    ctx.lineWidth = 1;
                    for (const f of [0.5, 1]) {
                        const y = Math.round(base - (base - top) * f) + 0.5;
                        ctx.beginPath();
                        ctx.moveTo(0, y);
                        ctx.lineTo(w, y);
                        ctx.stroke();
                    }

                    for (let i = 0; i < n; i++) {
                        const d = root.days[i];
                        const x = i * slot + (slot - barW) / 2;
                        if (i === root.hovered) {
                            ctx.fillStyle = Qt.rgba(root.colGuide.r, root.colGuide.g, root.colGuide.b, 0.07);
                            ctx.fillRect(i * slot, 0, slot, h);
                        }
                        if (!d.row) {
                            // No data: a dot, not a zero.
                            ctx.fillStyle = Qt.rgba(root.colGuide.r, root.colGuide.g, root.colGuide.b, 0.18);
                            ctx.beginPath();
                            ctx.arc(i * slot + slot / 2, base - 2, 1.5, 0, Math.PI * 2);
                            ctx.fill();
                            continue;
                        }
                        let y = base;
                        const parts = [[d.row.failed, root.colFailed], [d.row.crashes, root.colCrashes], [d.row.newErrors, root.colErrors]];
                        for (const [v, col] of parts) {
                            const bh = Number(v ?? 0) * scale;
                            if (bh <= 0)
                                continue;
                            ctx.fillStyle = col;
                            ctx.fillRect(x, y - bh, barW, bh);
                            y -= bh + 1;
                        }
                        if (y === base) {
                            // A clean day: a short tick on the baseline.
                            ctx.fillStyle = Qt.rgba(root.colGuide.r, root.colGuide.g, root.colGuide.b, 0.25);
                            ctx.fillRect(x, base - 2, barW, 2);
                        }
                    }

                    // The line, broken over days without data.
                    const field = root.lineField;
                    ctx.strokeStyle = root.colLine;
                    ctx.lineWidth = 2;
                    ctx.lineJoin = "round";
                    let drawing = false;
                    let last = null;
                    ctx.beginPath();
                    for (let i = 0; i < n; i++) {
                        const row = root.days[i].row;
                        // A day without a boot has no boot time: a gap, not a zero.
                        if (!row || (field === "bootMs" && !(Number(row.bootMs) > 0))) {
                            drawing = false;
                            continue;
                        }
                        const px = i * slot + slot / 2;
                        const py = base - (base - top) * Math.min(1, Number(row[field] ?? 0) / root.maxLine);
                        if (drawing)
                            ctx.lineTo(px, py);
                        else
                            ctx.moveTo(px, py);
                        drawing = true;
                        last = [px, py];
                    }
                    ctx.stroke();
                    if (last) {
                        ctx.fillStyle = root.colLine;
                        ctx.beginPath();
                        ctx.arc(last[0], last[1], 3, 0, Math.PI * 2);
                        ctx.fill();
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onPositionChanged: mouse => root.hovered = Math.max(0, Math.min(root.dayCount - 1, Math.floor(mouse.x / (width / root.dayCount))))
                onExited: root.hovered = -1
            }
        }

        // Legend: the three stacked colours and what the line is.
        Flow {
            Layout.fillWidth: true
            spacing: ClockStyle.gap

            Repeater {
                model: [
                    [root.colFailed, Translation.tr("Failed units")],
                    [root.colCrashes, Translation.tr("Crashes")],
                    [root.colErrors, Translation.tr("New errors")],
                    [root.colLine, root.series === "disk" ? Translation.tr("Root disk used") : root.series === "boot" ? Translation.tr("Boot time") : Translation.tr("Memory pressure peak")]
                ]
                RowLayout {
                    id: legendItem
                    required property var modelData
                    required property int index
                    readonly property bool line: legendItem.index === 3
                    spacing: 6
                    Rectangle {
                        implicitWidth: legendItem.line ? 14 : 9
                        implicitHeight: legendItem.line ? 2 : 9
                        radius: legendItem.line ? 1 : 2
                        color: legendItem.modelData[0]
                    }
                    StyledText {
                        text: legendItem.modelData[1]
                        font.pixelSize: ClockStyle.textSmall
                        color: ClockStyle.colSubtext
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: root.caption
            wrapMode: Text.Wrap
            font.pixelSize: ClockStyle.textSmall
            font.features: { "tnum": 1 }
            color: ClockStyle.colOnSurface
        }
    }
}
