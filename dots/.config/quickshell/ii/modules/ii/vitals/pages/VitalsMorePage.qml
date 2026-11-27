pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.usage
import qs.modules.ii.vitals.components

/**
 * More: every type without a page of its own (water, nutrition, mindfulness, glucose…,
 * and any type the registry does not know yet), one card each, drawn by its kind over the
 * chosen day, week or month: totals as columns, samples as daily ranges, sessions and
 * measurements as lists. Nothing here needs the type to be known in advance.
 */
VitalsPage {
    id: root

    // ── Period (as on Activity) ─────────────────────────────────────────
    property string granularity: "week"
    property int periodOffset: 0
    readonly property bool isDay: root.granularity === "day"
    readonly property var dates: {
        AppStats.todayDate;
        return AppStats.periodDates(root.granularity, root.periodOffset);
    }
    readonly property string today: VitalsFormat.dateOf(root.now)
    readonly property string oldest: VitalsService.dates.length > 0 ? VitalsService.dates[0] : root.today
    readonly property bool canGoBack: {
        const prev = AppStats.periodDates(root.granularity, root.periodOffset - 1);
        return prev.length > 0 && prev[prev.length - 1] >= root.oldest;
    }
    readonly property string periodWord: root.isDay ? Translation.tr("this day")
        : root.granularity === "week" ? Translation.tr("this week") : Translation.tr("this month")

    // ── Data ────────────────────────────────────────────────────────────
    readonly property var keys: VitalsTypes.keysFor("more", VitalsService.present)
    readonly property var rows: {
        VitalsService.dataVersion;
        return root.dates.map(d => VitalsService.summary(d));
    }
    /// Goals the phone sends for types on this page, by type key.
    readonly property var goals: ({
        hydrationMl: Number(VitalsService.meta?.goals?.waterMl) || 0,
        intakeKcal: Number(VitalsService.meta?.goals?.intakeKcal) || 0
    })
    /// Sessions of the period by key, newest first: [{date, start, end, type}], from day files.
    property var sessionLists: ({})
    /// Hourly values of the chosen day by key, from its day file.
    property var hourly: ({})
    /// Day files are cached 14 at a time; asking for more would evict and re-read forever.
    readonly property int maxDayFiles: 8

    /// Whether a key's card has a chart or a list to draw for the period.
    function hasShape(key: string): bool {
        const kind = root.kindOf(key);
        if (kind === "totals" || kind === "scores")
            return root.isDay ? root.hourly[key] !== undefined : root.rows.some(r => (r?.t?.[key] ?? r?.sc?.[key]) !== undefined);
        if (kind === "samples")
            return !root.isDay && root.rows.some(r => r?.s?.[key] !== undefined);
        if (kind === "sessions")
            return root.rows.some(r => (r?.n?.[key] ?? 0) > 0);
        return root.rows.some(r => r?.m?.[key] !== undefined);
    }

    readonly property var fullKeys: root.keys.filter(k => root.hasShape(k))
    readonly property var shortKeys: root.keys.filter(k => !root.hasShape(k))

    /// The kind a key is filed under: the registry's, else whichever group of the index has it.
    function kindOf(key: string): string {
        const known = VitalsTypes.info(key).kind;
        if (known !== "")
            return known;
        const groups = { t: "totals", s: "samples", n: "sessions", m: "measurements", sc: "scores" };
        for (let i = VitalsService.dates.length - 1; i >= 0; i--) {
            const s = VitalsService.summary(VitalsService.dates[i]);
            for (const g in groups)
                if (s?.[g]?.[key] !== undefined)
                    return groups[g];
        }
        return "";
    }

    function refresh(): void {
        const sessionKeys = root.keys.filter(k => root.kindOf(k) === "sessions");
        // The newest days of the period that have sessions, shared by every sessions key.
        const want = [];
        for (let i = root.dates.length - 1; i >= 0 && want.length < root.maxDayFiles; i--)
            if (sessionKeys.some(k => (root.rows[i]?.n?.[k] ?? 0) > 0))
                want.push(root.dates[i]);
        const lists = {};
        for (const k of sessionKeys)
            lists[k] = [];
        for (const d of want) {
            const day = VitalsService.day(d);
            for (const k of sessionKeys)
                for (const s of (day?.sessions?.[k] ?? []))
                    lists[k].push({ date: d, start: s.start, end: s.end, type: s.type ?? "" });
        }
        for (const k of sessionKeys)
            lists[k].sort((a, b) => b.start - a.start);
        root.sessionLists = lists;

        const hours = {};
        if (root.isDay && root.dates.length > 0) {
            const totals = VitalsService.day(root.dates[0])?.totals ?? {};
            for (const k of root.keys)
                if (Array.isArray(totals[k]?.hourly))
                    hours[k] = totals[k].hourly;
        }
        root.hourly = hours;
    }

    function setGranularity(key: string): void {
        root.granularity = key;
        root.periodOffset = 0;
    }

    function stepPeriod(delta: int): void {
        if ((delta < 0 && !root.canGoBack) || (delta > 0 && root.periodOffset >= 0))
            return;
        root.periodOffset += delta;
    }

    function digits(v: real): string {
        return Number(v).toLocaleString(Qt.locale(), "f", 0);
    }

    Component.onCompleted: root.refresh()
    onDatesChanged: Qt.callLater(root.refresh)
    onKeysChanged: Qt.callLater(root.refresh)

    Connections {
        target: VitalsService
        function onDataVersionChanged() {
            root.refresh();
        }
        function onDayLoaded(date) {
            if (root.dates.includes(date))
                root.refresh();
        }
    }

    pageSubtitle: [
        AppStats.periodLabel(root.granularity, root.periodOffset),
        VitalsService.lastSync > 0 ? Translation.tr("data as of %1").arg(VitalsFormat.asOf(VitalsService.lastSync, null, root.now)) : ""
    ].filter(s => s.length > 0).join(" · ")

    function handleKey(key: int, modifiers: int): bool {
        // Ctrl/Alt/Super combinations are the window's (page switching, close, settings).
        if (modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
            return false;
        if (key === Qt.Key_PageUp || key === Qt.Key_PageDown) {
            const order = ["day", "week", "month"];
            const at = order.indexOf(root.granularity) + (key === Qt.Key_PageUp ? 1 : -1);
            if (at >= 0 && at < order.length)
                root.setGranularity(order[at]);
            return true;
        }
        if (key === Qt.Key_Home) {
            root.periodOffset = 0;
            return true;
        }
        if (key === Qt.Key_Left || key === Qt.Key_Right) {
            root.stepPeriod(key === Qt.Key_Left ? -1 : 1);
            return true;
        }
        return false;
    }

    // ── Layout ──────────────────────────────────────────────────────────
    readonly property real gap: ClockStyle.gap
    readonly property real contentWidth: root.width - ClockStyle.gapTiny * 2
    readonly property real contentLayoutWidth: root.layoutWidth - ClockStyle.gapTiny * 2
    readonly property int columns: root.compact ? 1 : Math.max(1, Math.floor((root.contentLayoutWidth + root.gap) / (320 + root.gap)))
    readonly property real cardWidth: Math.floor((root.contentLayoutWidth - root.gap * (root.columns - 1)) / root.columns)
    readonly property int cardHeight: 286
    readonly property int shortCardHeight: 136

    StyledFlickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight + ClockStyle.gapTiny + ClockStyle.fabClearance
        clip: true

        ColumnLayout {
            id: column
            x: ClockStyle.gapTiny
            y: ClockStyle.gapTiny
            width: Math.max(root.contentWidth, root.contentLayoutWidth)
            spacing: root.gap

            // The period every card below reads, set straight on the page.
            UsagePeriodControls {
                Layout.fillWidth: true
                Layout.leftMargin: ClockStyle.gapSmall
                Layout.rightMargin: ClockStyle.gapSmall
                granularity: root.granularity
                periodOffset: root.periodOffset
                canGoBack: root.canGoBack
                colContent: ClockStyle.colOnSurface
                colPane: ClockStyle.colBackground
                onGranularityPicked: key => root.setGranularity(key)
                onStepped: delta => root.stepPeriod(delta)
                onPeriodReset: root.periodOffset = 0
            }

            // Cards with something to draw, then the ones that only have a line to say,
            // in a flow of their own so a short card never leaves a hole beside a tall one.
            Flow {
                Layout.fillWidth: true
                // An emptied Flow keeps its last height; hidden, the layout gives it none.
                visible: root.fullKeys.length > 0
                spacing: root.gap

                move: Transition {
                    enabled: !ClockStyle.reducedMotion
                    NumberAnimation {
                        properties: "x,y"
                        duration: ClockStyle.motionDefault.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: ClockStyle.motionDefault.bezierCurve
                    }
                }

                Repeater {
                    model: ScriptModel {
                        values: root.fullKeys
                    }

                    MoreCard {
                        full: true
                    }
                }
            }

            Flow {
                Layout.fillWidth: true
                // An emptied Flow keeps its last height; hidden, the layout gives it none.
                visible: root.shortKeys.length > 0
                spacing: root.gap

                move: Transition {
                    enabled: !ClockStyle.reducedMotion
                    NumberAnimation {
                        properties: "x,y"
                        duration: ClockStyle.motionDefault.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: ClockStyle.motionDefault.bezierCurve
                    }
                }

                Repeater {
                    model: ScriptModel {
                        values: root.shortKeys
                    }

                    MoreCard {
                        full: false
                    }
                }
            }
        }
    }

    component MoreCard: Rectangle {
        id: card
        required property var modelData
        required property int index
        /// Tall with a chart or a list; short when the period only has a line to say.
        property bool full: true
        readonly property string key: String(card.modelData)
        readonly property string kind: root.kindOf(card.key)
        readonly property var info: VitalsTypes.info(card.key, card.kind)
        readonly property bool amounts: card.kind === "totals" || card.kind === "scores"
        /// One value per day of the period (totals, scores, sample means), null where none.
        readonly property var values: root.rows.map(r => r?.t?.[card.key] ?? r?.sc?.[card.key] ?? null)
        readonly property var known: card.values.filter(v => v !== null)
        readonly property var ranges: root.rows.map(r => {
            const s = r?.s?.[card.key];
            return s ? { min: s[0], avg: s[1], max: s[2] } : null;
        })
        readonly property int rangeDays: card.ranges.filter(r => r !== null).length
        readonly property var measurements: root.rows.map((r, i) => r?.m?.[card.key] ? { date: root.dates[i], entry: r.m[card.key] } : null)
            .filter(m => m !== null).reverse()
        readonly property int sessionCount: root.rows.reduce((a, r) => a + (r?.n?.[card.key] ?? 0), 0)
        readonly property bool empty: card.amounts ? card.known.length === 0
            : card.kind === "samples" ? card.rangeDays === 0
            : card.kind === "sessions" ? card.sessionCount === 0
            : card.measurements.length === 0

        width: root.cardWidth
        height: card.full ? root.cardHeight : root.shortCardHeight
        radius: VitalsStyle.radiusTile
        color: VitalsStyle.colTile

        Behavior on width {
            enabled: !ClockStyle.reducedMotion
            animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
        }

        StaggeredEntrance {
            index: card.index
            active: !ClockStyle.reducedMotion
        }

        ColumnLayout {
            id: cardColumn
            anchors {
                fill: parent
                margins: VitalsStyle.tilePadding
                topMargin: VitalsStyle.tilePadding - 2
            }
            spacing: ClockStyle.gapSmall

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                MaterialSymbol {
                    text: card.info.icon
                    iconSize: ClockStyle.iconSmall + 2
                    fill: 1
                    color: VitalsStyle.colOnTile
                }

                StyledText {
                    Layout.fillWidth: true
                    text: card.info.label
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textNormal
                    font.weight: Font.DemiBold
                    color: VitalsStyle.colOnTile
                }
            }

            // The period in one line: an amount for totals, a range for samples, a count otherwise.
            StyledText {
                Layout.fillWidth: true
                visible: !card.empty
                text: {
                    if (card.empty)
                        return "";
                    if (card.amounts) {
                        const total = card.known.reduce((a, b) => a + b, 0);
                        return VitalsTypes.format(card.key, card.kind === "scores" ? total / card.known.length : total);
                    }
                    if (card.kind === "samples") {
                        const k = card.ranges.filter(r => r !== null);
                        return Translation.tr("%1–%2").arg(VitalsTypes.format(card.key, Math.min(...k.map(r => r.min))))
                            .arg(VitalsTypes.format(card.key, Math.max(...k.map(r => r.max))));
                    }
                    if (card.kind === "sessions")
                        return card.sessionCount === 1 ? Translation.tr("1 session") : Translation.tr("%1 sessions").arg(card.sessionCount);
                    return VitalsTypes.format(card.key, card.measurements[0].entry);
                }
                elide: Text.ElideRight
                font.family: ClockStyle.fontMain
                font.variableAxes: ClockStyle.axesDigits
                font.pixelSize: 34
                color: VitalsStyle.colOnTile
            }

            StyledText {
                Layout.fillWidth: true
                text: {
                    if (card.empty)
                        return Translation.tr("No data %1").arg(root.periodWord);
                    const goal = root.goals[card.key] ?? 0;
                    if (card.amounts) {
                        const total = card.known.reduce((a, b) => a + b, 0);
                        const parts = [];
                        if (!root.isDay && card.kind === "totals")
                            parts.push(Translation.tr("%1 a day").arg(VitalsTypes.format(card.key, total / card.known.length)));
                        if (!root.isDay && card.kind === "scores")
                            parts.push(Translation.tr("average over %1 days").arg(card.known.length));
                        if (goal > 0)
                            parts.push(Translation.tr("goal %1 a day").arg(VitalsTypes.format(card.key, goal)));
                        return parts.join(" · ");
                    }
                    if (card.kind === "samples")
                        return Translation.tr("lowest to highest over %1 days").arg(card.rangeDays);
                    if (card.kind === "sessions")
                        return root.periodWord;
                    return Translation.tr("latest of %1 · %2").arg(card.measurements.length).arg(VitalsFormat.dayLabel(card.measurements[0].date, root.now));
                }
                elide: Text.ElideRight
                font.pixelSize: ClockStyle.textSmall
                color: VitalsStyle.colOnTileVariant
            }

            // ── Totals and scores: columns over the period (the day by the hour) ──
            UsageHistogram {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.topMargin: ClockStyle.gapSmall
                visible: card.amounts && !card.empty && (!root.isDay || root.hourly[card.key] !== undefined)
                values: root.isDay ? (root.hourly[card.key] ?? []) : card.values.map(v => v ?? 0)
                labels: root.isDay
                    ? Array.from({ length: 24 }, (_, h) => String(h).padStart(2, "0"))
                    : root.dates.map(d => root.granularity === "week"
                        ? Qt.locale().toString(new Date(Number(d.slice(0, 4)), Number(d.slice(5, 7)) - 1, Number(d.slice(8, 10))), "ddd")
                        : String(Number(d.slice(8, 10))))
                tooltipLabels: root.isDay ? Array.from({ length: 24 }, (_, h) => String(h).padStart(2, "0") + ":00")
                    : root.dates.map(d => VitalsFormat.dayLabel(d, root.now))
                nowIndex: root.isDay ? -1 : root.dates.indexOf(root.today)
                labelStride: root.isDay ? 6 : 1
                labelAnchorEnd: !root.isDay
                formatValue: v => VitalsTypes.format(card.key, v)
                formatTick: v => VitalsTypes.format(card.key, v)
                emptyText: Translation.tr("No data %1").arg(root.periodWord)
                colContent: VitalsStyle.colOnTile
                colPane: VitalsStyle.colTile
            }

            // ── Samples: one range per day ──
            VitalsGenericRangeBars {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.topMargin: ClockStyle.gapSmall
                visible: card.kind === "samples" && !card.empty && !root.isDay
                ranges: card.ranges
                labels: root.dates.map(d => String(Number(d.slice(8, 10))))
                tooltipLabels: root.dates.map(d => VitalsFormat.dayLabel(d, root.now))
                selectedIndex: root.dates.indexOf(root.today)
                colBar: ClockStyle.colTertiary
                colContent: VitalsStyle.colOnTile
                colPane: VitalsStyle.colTile
                formatValue: v => VitalsTypes.format(card.key, v)
            }

            // ── Sessions and measurements: a list, newest first ──
            ColumnLayout {
                id: list
                readonly property int rowHeight: 40
                readonly property var items: card.kind === "sessions"
                    ? (root.sessionLists[card.key] ?? []).map(s => ({
                        head: VitalsFormat.dayLabel(s.date, root.now) + " · " + VitalsFormat.clock(s.start) + "–" + VitalsFormat.clock(s.end),
                        value: VitalsTypes.duration((s.end - s.start) / 60000)
                    }))
                    : card.measurements.map(m => ({
                        head: VitalsFormat.dayLabel(m.date, root.now) + (m.entry.time ? " · " + VitalsFormat.clock(m.entry.time) : ""),
                        value: VitalsTypes.format(card.key, m.entry)
                    }))
                readonly property int fits: Math.max(1, Math.floor((list.height + ClockStyle.gapTiny) / (list.rowHeight + ClockStyle.gapTiny)))
                // The sessions loaded cover the newest days only; the count above covers all.
                readonly property int hidden: (card.kind === "sessions" ? card.sessionCount : list.items.length) - Math.min(list.items.length, list.fits - 1)

                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.topMargin: ClockStyle.gapSmall
                visible: (card.kind === "sessions" || card.kind === "measurements") && !card.empty
                spacing: ClockStyle.gapTiny
                clip: true

                Repeater {
                    model: list.items.slice(0, list.hidden > 0 ? list.fits - 1 : list.fits)

                    Rectangle {
                        id: listRow
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: list.rowHeight
                        radius: ClockStyle.radiusSmall
                        color: Appearance.colors.colLayer2

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: ClockStyle.gap
                            anchors.rightMargin: ClockStyle.gap
                            spacing: ClockStyle.gapSmall

                            StyledText {
                                Layout.fillWidth: true
                                text: listRow.modelData.head
                                elide: Text.ElideRight
                                font.pixelSize: ClockStyle.textSmall
                                color: ClockStyle.colOnSurfaceVariant
                            }

                            StyledText {
                                text: listRow.modelData.value
                                font.pixelSize: ClockStyle.textSmall
                                font.weight: Font.Bold
                                color: ClockStyle.colOnSurface
                            }
                        }
                    }
                }

                StyledText {
                    visible: list.hidden > 0
                    Layout.leftMargin: ClockStyle.gap
                    text: Translation.tr("and %1 more %2").arg(list.hidden).arg(root.periodWord)
                    font.pixelSize: ClockStyle.textSmall
                    color: VitalsStyle.colOnTileVariant
                }

                Item {
                    Layout.fillHeight: true
                }
            }

            // A quiet line where the period has nothing, or where a single day has no shape to draw.
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: card.empty || (root.isDay && (card.amounts ? root.hourly[card.key] === undefined : card.kind === "samples"))
            }
        }
    }
}
