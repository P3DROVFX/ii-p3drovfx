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
import qs.modules.ii.usage.limits
import "UsageFormat.js" as Format

/**
 * The App usage tab: per-app screen time, focus, energy, CPU and GPU for a day, a week
 * or a month.
 *
 * Laid out like the Limits page. A primary hero pane holds the one figure the page is
 * about — the period's total for the chosen metric in tall digits, the change against
 * the period before, the period controls and the histogram — and the ranked app list
 * sits beside it (or under it on a narrow window).
 *
 * Picking an app narrows the hero to it rather than swapping the page: the question is
 * almost always "how does this one compare to the rest of the day", and losing the
 * list loses that. The side sheet then carries every figure for that app.
 */
Item {
    id: root

    // ── Page contract ───────────────────────────────────────────────────
    property bool compact: false
    /// The page's settled width from the shell (its own width once the rail has
    /// finished folding); `width` animates in between.
    property real layoutWidth: width
    /// Shared with the shell, which persists granularity and metric: string
    /// granularity, string metricKey, int periodOffset (<= 0), string selectedKey.
    required property QtObject viewState

    /// "Set a daily limit" from the app sheet; the shell opens the Limits tab on it.
    signal limitRequested(string appKey)

    readonly property string pageSubtitle: AppStats.periodLabel(root.granularity, root.periodOffset) + " · "
        + (root.ranked.length > 0 ? Translation.tr("%1 apps").arg(root.ranked.length) : Translation.tr("No activity"))
    readonly property bool detailOpen: false
    readonly property string detailTitle: ""

    function closeDetail(): void {
    }

    function handleEscape(): bool {
        if (sidePanel.open) {
            sidePanel.close();
            return true;
        }
        if (root.focusedBucket >= 0) {
            root.focusedBucket = -1;
            return true;
        }
        if (root.selectedKey.length > 0) {
            root.clearSelection();
            return true;
        }
        return false;
    }

    /// Tab cycles the metric rather than one digit per metric: on an AZERTY keyboard the
    /// number row needs Shift, so digits alone would leave half the page unreachable.
    /// They still work where they are unshifted.
    function handleKey(key: int, modifiers: int): bool {
        // Ctrl/Alt/Super combinations are the window's (tab switching, close, settings).
        if (modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
            return false;
        if (key >= Qt.Key_1 && key < Qt.Key_1 + root.metrics.length) {
            root.setMetric(root.metrics[key - Qt.Key_1].key);
            return true;
        }
        switch (key) {
        case Qt.Key_Tab:
            root.setMetric(root.metrics[(root.metricIndex + 1) % root.metrics.length].key);
            return true;
        case Qt.Key_Backtab:
            root.setMetric(root.metrics[(root.metricIndex + root.metrics.length - 1) % root.metrics.length].key);
            return true;
        case Qt.Key_Left:
            root.stepPeriod(-1);
            return true;
        case Qt.Key_Right:
            root.stepPeriod(1);
            return true;
        case Qt.Key_PageUp:
            root.setGranularity(root.granularities[Math.min(2, root.granularityIndex + 1)]);
            return true;
        case Qt.Key_PageDown:
            root.setGranularity(root.granularities[Math.max(0, root.granularityIndex - 1)]);
            return true;
        case Qt.Key_Home:
            root.resetPeriod();
            return true;
        case Qt.Key_Up:
            root.moveSelection(-1);
            return true;
        case Qt.Key_Down:
            root.moveSelection(1);
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (root.selectedKey.length === 0)
                return false;
            root.openSheet();
            return true;
        }
        return false;
    }

    // ── Layout ──────────────────────────────────────────────────────────
    readonly property real sheetWidth: root.compact ? root.width
        : Math.max(ClockStyle.sheetWidthMin, Math.min(ClockStyle.sheetWidth + 20, root.layoutWidth * 0.3))
    /// Settled page width: the shell's settled width minus this page's own open sheet.
    /// Every layout decision reads this, not the live width, so neither the rail folding
    /// nor a sheet sliding in reflows the page every frame.
    readonly property real pageLayoutWidth: root.compact ? root.layoutWidth
        : root.layoutWidth - (sidePanel.open ? root.sheetWidth + ClockStyle.paneGap : 0)
    readonly property bool wide: !root.compact && root.pageLayoutWidth >= 820
    readonly property real heroWidth: root.wide
        ? Math.round(Math.max(420, Math.min(root.pageLayoutWidth - 360, root.pageLayoutWidth * 0.56)))
        : root.pageLayoutWidth
    readonly property real figureSize: Math.round(Math.max(44, Math.min(92, root.heroWidth * 0.15)))
    readonly property real statFigureSize: Math.round(Math.max(24, Math.min(36, root.heroWidth * 0.062)))

    // ── Metrics ─────────────────────────────────────────────────────────
    readonly property var granularities: ["day", "week", "month"]

    /// `fields` are summed straight out of a stored hour tuple, so a metric that spans
    /// several of them (energy is foreground plus background) needs no special case in
    /// the chart or the list.
    readonly property var metrics: [
        { key: "fg", icon: "schedule", name: Translation.tr("Screen time"), fields: ["fg"], kind: "duration" },
        { key: "focus", icon: "point_scan", name: Translation.tr("Focused"), fields: ["focus"], kind: "duration" },
        { key: "energy", icon: "bolt", name: Translation.tr("Energy"), fields: ["mjFg", "mjBg"], kind: "energy" },
        { key: "cpu", icon: "memory", name: Translation.tr("CPU"), fields: ["cpu"], kind: "duration" },
        { key: "gpu", icon: "stadia_controller", name: Translation.tr("GPU"), fields: ["gpu"], kind: "duration" }
    ]

    readonly property int metricIndex: Math.max(0, root.metrics.findIndex(m => m.key === root.viewState.metricKey))
    readonly property var metric: root.metrics[root.metricIndex]
    readonly property string granularity: root.granularities.includes(root.viewState.granularity)
        ? root.viewState.granularity : "day"
    readonly property int granularityIndex: root.granularities.indexOf(root.granularity)
    /// Periods back from the current one. Never positive: nothing ahead of now to see.
    readonly property int periodOffset: Math.min(0, root.viewState.periodOffset)
    readonly property string selectedKey: root.viewState.selectedKey ?? ""
    /// The hour or day the page is narrowed to, or -1 for the whole period.
    property int focusedBucket: -1

    /// Kept in the config rather than here so the chart, which asks the service
    /// directly, cannot end up filtering differently from the list.
    readonly property bool showHeadless: AppStats.showHeadless
    /// Apps under this many seconds drop out of the list — not out of the totals,
    /// which are what the machine actually did.
    readonly property int minDuration: Config.options.appStats?.minDurationSec ?? 0
    readonly property bool showComparison: Config.options.appStats?.showComparison ?? false
    readonly property bool limitsOn: Config.options.screenTime?.enable ?? true

    readonly property bool isSingleDay: root.granularity === "day"
    readonly property var dates: AppStats.periodDates(root.granularity, root.periodOffset)
    readonly property bool canGoBack: AppStats.hasEarlierPeriod(root.granularity, root.periodOffset)
    /// The hour a day is narrowed to, or -1.
    readonly property int focusedHour: root.isSingleDay ? root.focusedBucket : -1

    function setMetric(key: string): void {
        root.viewState.metricKey = key;
    }

    function stepPeriod(delta: int): void {
        const next = Math.min(0, root.periodOffset + delta);
        if (next === root.periodOffset)
            return;
        if (next < root.periodOffset && !root.canGoBack)
            return;
        root.viewState.periodOffset = next;
        root.focusedBucket = -1;
    }

    /// Changing granularity keeps you in the present rather than at whatever offset the
    /// last one was on — three weeks back and three months back are different places,
    /// and silently jumping between them reads as broken data.
    function setGranularity(key: string): void {
        if (root.granularity === key)
            return;
        root.viewState.granularity = key;
        root.viewState.periodOffset = 0;
        root.focusedBucket = -1;
    }

    function resetPeriod(): void {
        root.viewState.periodOffset = 0;
        root.focusedBucket = -1;
    }

    function focusBucket(index: int): void {
        root.focusedBucket = root.focusedBucket === index ? -1 : index;
    }

    function refresh(): void {
        AppStats.ensureDates(root.dates);
        AppStats.refresh();
    }

    // ── Figures ─────────────────────────────────────────────────────────
    readonly property var targetDates: {
        if (root.focusedBucket >= 0 && !root.isSingleDay) {
            const date = root.dates[root.focusedBucket];
            return date ? [date] : root.dates;
        }
        return root.dates;
    }

    readonly property var summary: {
        // Touching `history` here is what makes every derived figure recompute when a
        // day file lands; `dates` alone does not change when the data does.
        AppStats.history;
        const opts = {
            headless: root.showHeadless
        };
        if (root.focusedHour >= 0) {
            opts.hourFrom = root.focusedHour;
            opts.hourTo = root.focusedHour;
        }
        return AppStats.summarize(root.targetDates, opts);
    }

    /// Apps carrying a nonzero value for the selected metric, largest first. The
    /// unattributed remainder joins the list only for energy, the one metric it holds.
    readonly property var ranked: {
        // A threshold in seconds says nothing about watt-hours, so it is applied to the
        // metrics it can be read in and ignored for the rest.
        const floor = root.metric.kind === "duration" ? root.minDuration : 0;
        const list = root.summary.apps.filter(rec => root.metricValue(rec) > floor);
        if (root.metric.key === "energy" && root.metricValue(root.summary.system) > 0)
            list.push(root.summary.system);
        list.sort((a, b) => root.metricValue(b) - root.metricValue(a));
        return list;
    }
    readonly property real rankedMax: root.ranked.length > 0 ? root.metricValue(root.ranked[0]) : 0

    readonly property var selectedRecord: {
        for (const rec of root.ranked) {
            if (rec.key === root.selectedKey)
                return rec;
        }
        return null;
    }

    /// The selected metric over everything in scope. Screen time is the device's own
    /// figure rather than the sum of the list: two windows on screen are one hour of
    /// screen time.
    readonly property real metricTotal: root.totalFor(root.summary, root.targetDates, root.selectedKey, root.focusedHour)
    /// The same over every app, for the selected app's share.
    readonly property real overallTotal: root.selectedKey.length > 0
        ? root.totalFor(root.summary, root.targetDates, "", root.focusedHour) : root.metricTotal
    readonly property real selectedShare: root.selectedRecord && root.overallTotal > 0
        ? Math.min(1, root.metricValue(root.selectedRecord) / root.overallTotal) : -1

    /// The figure the hero leads with, for any period. Taken off the summary rather
    /// than off `ranked`, so a listing threshold cannot quietly shrink the total it was
    /// never meant to touch.
    function totalFor(summary, dates, key: string, hour: int): real {
        if (key.length > 0) {
            if (key === AppStats.systemKey)
                return root.metricValue(summary.system);
            for (const rec of summary.apps) {
                if (rec.key === key)
                    return root.metricValue(rec);
            }
            return 0;
        }
        if (root.metric.key === "fg")
            return root.deviceScreenTimeFor(dates, hour);
        let total = summary.apps.reduce((sum, rec) => sum + root.metricValue(rec), 0);
        if (root.metric.key === "energy")
            total += root.metricValue(summary.system);
        return total;
    }

    function metricValue(rec): real {
        if (!rec)
            return 0;
        let sum = 0;
        for (const field of root.metric.fields)
            sum += rec[field] ?? 0;
        return sum;
    }

    function formatMetric(value: real): string {
        return root.metric.kind === "energy" ? Format.energyFromMj(value) : Format.duration(value);
    }

    /// Compact enough for the axis, where each tick has a gutter a few characters wide.
    function formatTick(value: real): string {
        return root.metric.kind === "energy" ? Format.energyFromMj(value) : Format.durationShort(value);
    }

    /// Screen time for a set of dates (one hour of them when `hour` is set), counted
    /// once rather than once per window.
    function deviceScreenTimeFor(dates, hour: int): real {
        return dates.reduce((total, date) => {
            const hours = AppStats.deviceHours(date, "fg");
            if (hour >= 0)
                return total + (hours[hour] ?? 0);
            return total + hours.reduce((sum, value) => sum + value, 0);
        }, 0);
    }

    /// Whose series the chart draws. With no app picked, screen time is asked of the
    /// device row instead of summed over the apps.
    readonly property string chartKey: {
        if (root.selectedKey.length > 0)
            return root.selectedKey;
        return root.metric.key === "fg" ? AppStats.systemKey : "";
    }

    function seriesFor(key): var {
        const length = root.isSingleDay ? 24 : root.dates.length;
        const out = new Array(length).fill(0);
        for (const field of root.metric.fields) {
            const series = root.isSingleDay
                ? AppStats.hourlySeries(root.dates, field, key)
                : AppStats.dailySeries(root.dates, field, key);
            for (let i = 0; i < length; i++)
                out[i] += series[i] ?? 0;
        }
        return out;
    }

    /// One value per bucket for the device as a whole. Built from hours rather than
    /// from a day total, because that is the resolution its fallback works at.
    function deviceSeries(field: string): var {
        const perDay = root.dates.map(date => AppStats.deviceHours(date, field));
        if (root.isSingleDay)
            return perDay[0] ?? new Array(24).fill(0);
        return perDay.map(hours => hours.reduce((sum, value) => sum + value, 0));
    }

    /// The chart series for the current range, metric and selection.
    readonly property var chartValues: {
        AppStats.history;
        // The device series is screen time and nothing else; drawing it whenever the
        // system row was the subject put seconds under a watt-hour axis.
        if (root.metric.key === "fg" && root.chartKey === AppStats.systemKey)
            return root.deviceSeries("fg");
        if (root.selectedKey.length > 0)
            return root.seriesFor(root.selectedKey);

        const values = root.seriesFor(null);
        if (root.metric.key !== "energy")
            return values;

        // The share that belongs to no app is still energy the machine spent, and the
        // list already carries it as a row; leaving it out of the chart alone would put
        // three totals for one metric on one screen.
        const system = root.seriesFor(AppStats.systemKey);
        return values.map((value, index) => value + (system[index] ?? 0));
    }

    /// The period before the one on screen, for the comparison line.
    ///
    /// Its files are loaded a beat after the current period rather than with it: a month
    /// view already parses thirty-odd of them on the main thread, and doubling that at
    /// the moment the page opens is felt.
    readonly property var previousDates: root.showComparison
        ? AppStats.periodDates(root.granularity, root.periodOffset - 1) : []
    property bool comparisonReady: false

    readonly property real previousTotal: {
        AppStats.history;
        if (!root.comparisonReady || root.previousDates.length === 0)
            return -1;
        const summary = AppStats.summarize(root.previousDates, {
            headless: root.showHeadless
        });
        return root.totalFor(summary, root.previousDates, root.selectedKey, -1);
    }

    /// Percent change against the period before, or NaN when there is nothing to
    /// compare with — a period with no data reads as "-100 %" otherwise, which says the
    /// machine was idle rather than that it was not yet recording. A narrowed bucket is
    /// not compared: an hour against the whole day before means nothing.
    readonly property real comparisonDelta: {
        if (root.focusedBucket >= 0 || root.previousTotal <= 0 || root.metricTotal <= 0)
            return NaN;
        return (root.metricTotal - root.previousTotal) / root.previousTotal * 100;
    }

    Timer {
        id: comparisonTimer
        interval: 400
        onTriggered: {
            AppStats.ensureDates(root.previousDates);
            root.comparisonReady = true;
        }
    }

    onPreviousDatesChanged: {
        root.comparisonReady = false;
        if (root.previousDates.length > 0)
            comparisonTimer.restart();
    }

    /// Every `dayStride`-th label is drawn, counted back from today.
    readonly property int dayStride: Math.max(1, Math.ceil(root.dates.length / 10))

    /// Which bucket is now, or -1 in a period that is already over — a past week has no
    /// current column, and marking one would date the chart wrong.
    readonly property int nowIndex: {
        if (root.dates.length === 0)
            return -1;
        if (root.isSingleDay)
            return root.periodOffset === 0 ? DateTime.clock.date.getHours() : -1;
        return root.dates[root.dates.length - 1] === AppStats.todayDate ? root.dates.length - 1 : -1;
    }

    readonly property var chartLabels: {
        if (root.isSingleDay)
            return Array.from({ length: 24 }, (unused, hour) => Format.hourLabel(hour));
        // Spelled out at both ends and wherever a month turns over, so the range says
        // where in the year it sits.
        const first = (root.dates.length - 1) % root.dayStride;
        return root.dates.map((date, index) => Format.dayLabel(date,
            index === first || index === root.dates.length - 1 || date.slice(-2) === "01"));
    }

    readonly property var bucketNames: {
        if (root.isSingleDay)
            return root.chartLabels;
        return root.dates.map(date => new Date(date + "T12:00:00").toLocaleDateString(Qt.locale(), "ddd d MMM"));
    }

    readonly property string scopeTitle: {
        if (root.selectedKey.length > 0)
            return AppStats.displayName(root.selectedKey);
        if (root.metric.key === "fg")
            return Translation.tr("Device screen time");
        if (root.metric.key === "energy")
            return Translation.tr("Energy · device");
        return Translation.tr("%1 · all apps").arg(root.metric.name);
    }

    readonly property string periodText: AppStats.periodLabel(root.granularity, root.periodOffset)
        + (root.focusedBucket >= 0 ? " · " + (root.bucketNames[root.focusedBucket] ?? "") : "")

    /// Context under the headline: the figures it does not already say.
    readonly property var heroStats: {
        const rec = root.selectedRecord;
        const summary = root.summary;
        const list = [];
        if (root.metric.key !== "fg" && root.selectedKey !== AppStats.systemKey) {
            list.push({
                symbol: "schedule",
                label: rec ? Translation.tr("Screen time") : Translation.tr("Device screen time"),
                value: Format.duration(rec ? rec.fg : root.deviceScreenTimeFor(root.targetDates, root.focusedHour))
            });
        }
        // Apps plus the share that belongs to none of them, matching the chart and the
        // list rather than counting the apps alone.
        if (root.metric.key !== "energy") {
            const energy = rec ? rec.mjFg + rec.mjBg
                : summary.totals.mjFg + summary.totals.mjBg + summary.system.mjFg + summary.system.mjBg;
            list.push({ symbol: "bolt", label: Translation.tr("Energy"), value: Format.energyFromMj(energy) });
        }
        list.push({
            symbol: "rocket_launch",
            label: Translation.tr("Launches"),
            value: Format.count(rec ? rec.launches : summary.totals.launches)
        });
        // Per-app watt-hours are modelled from CPU, GPU and memory shares, so the share
        // that belongs to no app is the honest measure of how much weight they carry.
        const system = summary.system.mjFg + summary.system.mjBg;
        const apps = summary.totals.mjFg + summary.totals.mjBg;
        if (!rec && system > 0) {
            list.push({
                symbol: "help",
                label: Translation.tr("Unattributed"),
                value: `${Math.round(system / (system + apps) * 100)} %`
            });
        }
        return list;
    }

    // ── Selection ───────────────────────────────────────────────────────
    function clearSelection(): void {
        root.viewState.selectedKey = "";
    }

    /// Picking an app narrows the hero to it and opens its sheet; picking it again
    /// clears both.
    function toggleApp(key: string): void {
        if (root.selectedKey === key) {
            root.clearSelection();
            return;
        }
        root.viewState.selectedKey = key;
        root.openSheet();
    }

    /// Moves the selection `delta` rows through the list, selecting the first row from
    /// nothing and falling off the top back to nothing.
    function moveSelection(delta: int): void {
        if (root.ranked.length === 0)
            return;
        const index = root.ranked.findIndex(rec => rec.key === root.selectedKey);
        const next = index + delta;
        if (next < 0) {
            root.clearSelection();
            return;
        }
        const clamped = Math.min(next, root.ranked.length - 1);
        root.viewState.selectedKey = root.ranked[clamped].key;
        root.revealRow(clamped);
    }

    function revealRow(index: int): void {
        if (wideLoader.item) {
            wideLoader.item.revealRow(index);
            return;
        }
        if (narrowLoader.item)
            narrowLoader.item.revealRow(index);
    }

    /// The sheet follows the selection through bindings, so arrowing through the list
    /// with it open retargets it instead of rebuilding it.
    function openSheet(): void {
        if (sidePanel.isShowing(appSheet))
            return;
        const sheet = sidePanel.show(appSheet, {});
        if (!sheet)
            return;
        sheet.appKey = Qt.binding(() => root.selectedKey);
        sheet.record = Qt.binding(() => root.selectedRecord);
        sheet.metricKey = Qt.binding(() => root.metric.key);
        sheet.share = Qt.binding(() => root.selectedShare);
        sheet.periodText = Qt.binding(() => root.periodText);
        sheet.limitRequested.connect(key => root.limitRequested(key));
        sheet.clearRequested.connect(() => root.clearSelection());
    }

    onSelectedKeyChanged: {
        if (root.selectedKey.length === 0 && sidePanel.isShowing(appSheet))
            sidePanel.close();
    }

    // A selection is only meaningful while the app is still in the list; changing
    // metric or range can drop it out entirely.
    onRankedChanged: {
        if (root.selectedKey.length > 0 && !root.selectedRecord)
            root.clearSelection();
    }

    onDatesChanged: AppStats.ensureDates(root.dates)
    // The shell asks the sampler for a fresh flush once the window has opened.
    Component.onCompleted: AppStats.ensureDates(root.dates)

    Component {
        id: appSheet
        UsageAppSheet {}
    }

    // ── Pieces ──────────────────────────────────────────────────────────
    /// The period's headline, controls and histogram on the primary pane.
    component Hero: Rectangle {
        id: hero

        readonly property color colPane: ClockStyle.colPrimary
        readonly property color colContent: ClockStyle.colOnPrimary

        implicitHeight: heroColumn.implicitHeight + (ClockStyle.cardPadding + 4) * 2
        radius: ClockStyle.radiusCard
        color: hero.colPane

        ColumnLayout {
            id: heroColumn
            anchors {
                fill: parent
                margins: ClockStyle.cardPadding + 4
            }
            spacing: ClockStyle.gap

            // ── Header ──────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall + 2

                MaterialShapeWrappedMaterialSymbol {
                    text: root.metric.icon
                    iconSize: 20
                    padding: 10
                    shape: MaterialShape.Shape.Clover4Leaf
                    color: hero.colContent
                    colSymbol: hero.colPane
                    fill: 1
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: root.scopeTitle
                        font.pixelSize: ClockStyle.textNormal + 1
                        font.weight: Font.DemiBold
                        color: hero.colContent
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.selectedKey.length > 0 ? `${root.metric.name} · ${root.periodText}` : root.periodText
                        font.pixelSize: ClockStyle.textSmall
                        color: hero.colContent
                        opacity: 0.8
                        elide: Text.ElideRight
                    }
                }

                LimitsTintButton {
                    symbol: "refresh"
                    height_: 38
                    colContent: hero.colContent
                    onClicked: root.refresh()

                    StyledToolTip {
                        text: Translation.tr("Refresh")
                    }
                }
            }

            // ── Headline ────────────────────────────────────────────
            UsageFigure {
                Layout.maximumWidth: heroColumn.width
                text: root.formatMetric(root.metricTotal)
                size: root.figureSize
                color: hero.colContent
            }

            // What the figure is narrowed to, and how it moved.
            Flow {
                Layout.fillWidth: true
                visible: comparisonPill.visible || root.focusedBucket >= 0 || root.selectedKey.length > 0
                spacing: ClockStyle.gapSmall

                // Neutral on purpose: more screen time is not worse and less energy is
                // not better without knowing what the machine was for.
                Rectangle {
                    id: comparisonPill
                    visible: root.showComparison && !isNaN(root.comparisonDelta)
                    width: comparisonRow.implicitWidth + ClockStyle.gapLarge * 2
                    height: 34
                    radius: ClockStyle.pill(height)
                    color: ColorUtils.applyAlpha(hero.colContent, 0.12)

                    RowLayout {
                        id: comparisonRow
                        anchors.centerIn: parent
                        spacing: ClockStyle.gapTiny + 2

                        MaterialSymbol {
                            text: root.comparisonDelta >= 0 ? "trending_up" : "trending_down"
                            iconSize: ClockStyle.iconSmall + 2
                            color: hero.colContent
                        }

                        StyledText {
                            text: isNaN(root.comparisonDelta) ? "" : Translation.tr("%1 %2 % vs %3")
                                .arg(root.comparisonDelta >= 0 ? "+" : "−")
                                .arg(Math.round(Math.abs(root.comparisonDelta)))
                                .arg(AppStats.periodLabel(root.granularity, root.periodOffset - 1))
                            font.pixelSize: ClockStyle.textNormal
                            font.weight: Font.DemiBold
                            color: hero.colContent
                        }
                    }
                }

                LimitsTintButton {
                    visible: root.focusedBucket >= 0
                    symbol: "close"
                    label: Translation.tr("Only %1").arg(root.bucketNames[root.focusedBucket] ?? "")
                    height_: 34
                    colContent: hero.colContent
                    onClicked: root.focusedBucket = -1

                    StyledToolTip {
                        text: Translation.tr("Clear time filter")
                    }
                }

                LimitsTintButton {
                    visible: root.selectedKey.length > 0
                    symbol: "close"
                    label: AppStats.displayName(root.selectedKey)
                    height_: 34
                    colContent: hero.colContent
                    onClicked: root.clearSelection()

                    StyledToolTip {
                        text: Translation.tr("Clear selection")
                    }
                }
            }

            UsagePeriodControls {
                Layout.fillWidth: true
                granularity: root.granularity
                periodOffset: root.periodOffset
                colContent: hero.colContent
                colPane: hero.colPane
                onGranularityPicked: key => root.setGranularity(key)
                onStepped: delta => root.stepPeriod(delta)
                onPeriodReset: root.resetPeriod()
            }

            // ── Histogram ───────────────────────────────────────────
            UsageHistogram {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 130
                Layout.preferredHeight: 170
                values: root.chartValues
                labels: root.chartLabels
                tooltipLabels: root.bucketNames
                nowIndex: root.nowIndex
                trimFuture: root.isSingleDay
                focusedIndex: root.focusedBucket
                labelStride: root.isSingleDay ? 4 : root.dayStride
                labelAnchorEnd: !root.isSingleDay
                timeScale: root.metric.kind === "duration"
                // Millijoules per watt-hour, the figure the axis is labelled in.
                valueUnit: root.metric.kind === "energy" ? 3600000 : 1
                formatValue: value => root.formatMetric(value)
                formatTick: value => root.formatTick(value)
                colContent: hero.colContent
                colPane: hero.colPane
                onBarClicked: index => root.focusBucket(index)
            }

            // ── Context ─────────────────────────────────────────────
            // Set straight on the pane, no tiles: a wide, square-cornered heavy caption
            // over a tall condensed figure, so type alone separates the two and the gaps
            // separate the stats.
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: ClockStyle.gapTiny
                spacing: ClockStyle.gapHuge

                Repeater {
                    model: root.heroStats

                    ColumnLayout {
                        id: heroStat
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        spacing: 0

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ClockStyle.gapTiny

                            MaterialSymbol {
                                text: heroStat.modelData.symbol
                                iconSize: ClockStyle.iconSmall - 2
                                fill: 1
                                color: hero.colContent
                                opacity: 0.7
                            }

                            StyledText {
                                id: statCaption
                                Layout.fillWidth: true
                                text: heroStat.modelData.label
                                font.family: ClockStyle.fontMain
                                font.variableAxes: ({ "wght": 800, "wdth": 125, "ROND": 0 })
                                font.pixelSize: Math.round(ClockStyle.textSmall - 1)
                                font.capitalization: Font.AllUppercase
                                font.letterSpacing: 0.6
                                color: hero.colContent
                                opacity: 0.75
                                elide: Text.ElideRight

                                HoverHandler {
                                    id: statCaptionHover
                                }
                                StyledToolTip {
                                    extraVisibleCondition: statCaptionHover.hovered && statCaption.truncated
                                    text: statCaption.text
                                }
                            }
                        }

                        UsageFigure {
                            Layout.maximumWidth: heroStat.width
                            text: heroStat.modelData.value
                            size: root.statFigureSize
                            color: hero.colContent
                        }
                    }
                }
            }
        }
    }

    /// Which figure the page is ranked by, and where its watt-hours come from.
    component MetricChips: ColumnLayout {
        spacing: ClockStyle.gapSmall

        Flow {
            Layout.fillWidth: true
            spacing: ClockStyle.gapSmall

            Repeater {
                model: root.metrics

                ClockChip {
                    id: metricChip
                    required property var modelData
                    required property int index
                    symbol: metricChip.modelData.icon
                    label: metricChip.modelData.name
                    selected: root.metric.key === metricChip.modelData.key
                    onClicked: root.setMetric(metricChip.modelData.key)

                    StyledToolTip {
                        text: Translation.tr("%1 (Tab, or %2)").arg(metricChip.modelData.name).arg(metricChip.index + 1)
                    }
                }
            }
        }

        // The energy source decides whether watt-hours are real counters or a
        // battery-drain guess, so it is stated rather than left to be inferred.
        RowLayout {
            Layout.leftMargin: ClockStyle.gapTiny
            visible: AppStats.running
            spacing: ClockStyle.gapTiny + 2

            MaterialSymbol {
                text: AppStats.source === "rapl" ? "electric_meter"
                    : AppStats.source === "battery" ? "battery_horiz_050" : "power_off"
                iconSize: ClockStyle.iconSmall
                color: ClockStyle.colSubtext
            }

            StyledText {
                text: {
                    switch (AppStats.source) {
                    case "rapl":
                        return Translation.tr("Energy from RAPL counters");
                    case "battery":
                        return Translation.tr("Energy estimated from battery drain");
                    default:
                        return Translation.tr("Energy unavailable");
                    }
                }
                font.pixelSize: ClockStyle.textSmall
                color: ClockStyle.colSubtext
            }
        }
    }

    /// The list pane's title row: how many apps, the background-services filter.
    component ListHeader: RowLayout {
        spacing: ClockStyle.gapSmall

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.ranked.length > 0 ? Translation.tr("%1 apps").arg(root.ranked.length) : Translation.tr("No activity")
                font.family: ClockStyle.fontTitle
                font.variableAxes: ClockStyle.axesTitle
                font.pixelSize: ClockStyle.textLarge + 2
                color: ClockStyle.colOnSurface
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Ranked by %1").arg(root.metric.name)
                font.pixelSize: ClockStyle.textSmall
                color: ClockStyle.colSubtext
                elide: Text.ElideRight
            }
        }

        // Not a list filter: it changes what the totals are counting too.
        ClockIconButton {
            symbol: "terminal"
            toggled: root.showHeadless
            tooltip: Translation.tr("Count background services in the list and the totals")
            onClicked: Config.options.appStats.showHeadless = !root.showHeadless
        }
    }

    /// One app: icon, name, its share as a bar drawn against the leader (so the top row
    /// always fills — against the total, a long tail collapses into stubs), the figure.
    component AppRow: Rectangle {
        id: row

        required property var modelData
        required property int index
        readonly property string appKey: row.modelData.key
        readonly property bool isSystem: row.appKey === AppStats.systemKey
        readonly property bool selected: root.selectedKey === row.appKey
        readonly property real value: root.metricValue(row.modelData)
        readonly property bool engaged: rowHover.hovered || limitButton.activeFocus

        implicitHeight: 64
        radius: row.selected ? ClockStyle.radiusLarge : ClockStyle.radiusNormal
        color: row.selected ? ClockStyle.colSecondaryContainer
            : row.engaged ? ClockStyle.colIdleCardHover : "transparent"

        Behavior on color {
            animation: ClockStyle.motionFast.colorAnimation.createObject(this)
        }
        Behavior on radius {
            enabled: !ClockStyle.reducedMotion
            animation: ClockStyle.motionFast.numberAnimation.createObject(this)
        }

        HoverHandler {
            id: rowHover
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleApp(row.appKey)
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: ClockStyle.gapSmall + 2
            anchors.rightMargin: ClockStyle.gap
            spacing: ClockStyle.gap

            Rectangle {
                implicitWidth: 44
                implicitHeight: 44
                radius: row.selected ? ClockStyle.radiusNormal : ClockStyle.pill(implicitHeight)
                color: row.selected ? ClockStyle.colSecondaryContainerHover : ClockStyle.colSurfaceHigh

                Behavior on radius {
                    enabled: !ClockStyle.reducedMotion
                    animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                }

                // Headless daemons and the system row have no desktop entry to draw
                // from; a window-bearing app that merely failed to resolve is not a
                // daemon, so it does not get the terminal glyph.
                LimitsAppIcon {
                    anchors.centerIn: parent
                    size: 30
                    appKey: row.isSystem ? "" : row.appKey
                    fallbackSymbol: row.isSystem ? "memory" : (row.modelData.headless ?? false) ? "terminal" : "apps"
                    colFallback: row.selected ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurfaceVariant
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapTiny + 2

                StyledText {
                    id: rowName
                    Layout.fillWidth: true
                    text: AppStats.displayName(row.appKey)
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textNormal + 1
                    font.weight: Font.DemiBold
                    color: row.selected ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface

                    HoverHandler {
                        id: rowNameHover
                    }
                    StyledToolTip {
                        extraVisibleCondition: rowNameHover.hovered && rowName.truncated
                        text: rowName.text
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 6
                    radius: ClockStyle.pill(implicitHeight)
                    color: row.selected
                        ? ColorUtils.applyAlpha(ClockStyle.colOnSecondaryContainer, 0.16) : ClockStyle.colSurfaceHigh

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: Math.max(parent.height,
                            parent.width * (root.rankedMax > 0 ? Math.min(1, row.value / root.rankedMax) : 0))
                        radius: parent.radius
                        color: row.isSystem ? ClockStyle.colSubtext
                            : row.selected ? ClockStyle.colOnSecondaryContainer : ClockStyle.colPrimary

                        Behavior on width {
                            enabled: !ClockStyle.reducedMotion
                            animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                        }
                    }
                }
            }

            // A fixed column, so the share bars of every row end in the same place.
            StyledText {
                Layout.minimumWidth: 96
                horizontalAlignment: Text.AlignRight
                text: root.formatMetric(row.value)
                font.family: ClockStyle.fontMain
                font.variableAxes: ClockStyle.axesDigitsBold
                font.pixelSize: 22
                color: row.selected ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface
            }

            Item {
                id: actionSlot
                readonly property bool available: root.limitsOn && !row.isSystem
                property real revealProgress: row.engaged && actionSlot.available ? 1 : 0

                Layout.preferredWidth: (limitButton.implicitWidth + 4) * actionSlot.revealProgress
                Layout.preferredHeight: limitButton.implicitHeight
                visible: actionSlot.available
                clip: true

                Behavior on revealProgress {
                    enabled: !ClockStyle.reducedMotion
                    animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                }

                ClockCardAction {
                    id: limitButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: actionSlot.revealProgress
                    enabled: row.engaged
                    symbol: "more_time"
                    tip: Translation.tr("Set a daily limit")
                    colContent: row.selected ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface
                    onClicked: root.limitRequested(row.appKey)
                }
            }
        }

        StaggeredEntrance {
            index: row.index
            step: ClockStyle.staggerStep / 2
            active: !ClockStyle.reducedMotion && row.index < 12
        }
    }

    /// Only meaningful once the sampler is up; before that an empty list means "not
    /// collecting yet", which is a different thing entirely.
    component ListEmpty: ClockEmptyState {
        symbol: AppStats.running ? "hourglass_empty" : "power_off"
        shape: "Flower"
        shapeSize: ClockStyle.emptyShapeSmall
        title: AppStats.running ? Translation.tr("Nothing yet") : Translation.tr("Not collecting")
        subtitle: AppStats.running ? Translation.tr("Nothing recorded for this period yet.")
            : Translation.tr("The usage sampler is not running.")
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── Page ────────────────────────────────────────────────────────
        Item {
            id: pageArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !(root.compact && sidePanel.open)
            clip: true

            // Wide: the hero on the left at full height, the ranked list beside it.
            Loader {
                id: wideLoader
                anchors.fill: parent
                active: root.wide
                visible: active
                sourceComponent: RowLayout {
                    spacing: ClockStyle.paneGap

                    function revealRow(index: int): void {
                        appList.positionViewAtIndex(index, ListView.Contain);
                    }

                    Hero {
                        Layout.preferredWidth: root.heroWidth
                        Layout.fillHeight: true

                        Behavior on Layout.preferredWidth {
                            enabled: !ClockStyle.reducedMotion
                            animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: ClockStyle.gap

                        MetricChips {
                            Layout.fillWidth: true
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: ClockStyle.radiusCard
                            color: ClockStyle.colPane

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: ClockStyle.gapSmall
                                anchors.topMargin: ClockStyle.gapLarge
                                spacing: ClockStyle.gapSmall

                                ListHeader {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: ClockStyle.gapSmall + 2
                                    Layout.rightMargin: ClockStyle.gapTiny
                                }

                                StyledListView {
                                    id: appList
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    spacing: 2
                                    // Keyed diff instead of a bare array: every history
                                    // update builds a new `ranked`, and an array model
                                    // tore down and rebuilt every row.
                                    model: ScriptModel {
                                        values: root.ranked
                                        objectProp: "key"
                                    }

                                    delegate: AppRow {
                                        width: appList.width
                                    }
                                }
                            }

                            ListEmpty {
                                anchors.centerIn: parent
                                width: Math.min(parent.width - ClockStyle.gapHuge * 2, 320)
                                visible: root.ranked.length === 0
                            }
                        }
                    }
                }
            }

            // Narrow: one scrolling column, the hero first.
            Loader {
                id: narrowLoader
                anchors.fill: parent
                active: !root.wide
                visible: active
                sourceComponent: StyledFlickable {
                    id: narrowFlick
                    contentWidth: width
                    contentHeight: narrowColumn.implicitHeight + ClockStyle.gapHuge
                    clip: true

                    function revealRow(index: int): void {
                        const row = rowRepeater.itemAt(index);
                        if (!row)
                            return;
                        const top = row.mapToItem(narrowColumn, 0, 0).y;
                        if (top < narrowFlick.contentY)
                            narrowFlick.contentY = top;
                        else if (top + row.height > narrowFlick.contentY + narrowFlick.height)
                            narrowFlick.contentY = Math.min(narrowFlick.contentHeight - narrowFlick.height,
                                top + row.height - narrowFlick.height);
                    }

                    ColumnLayout {
                        id: narrowColumn
                        width: narrowFlick.width
                        spacing: ClockStyle.paneGap

                        Hero {
                            Layout.fillWidth: true
                        }

                        MetricChips {
                            Layout.fillWidth: true
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: listColumn.implicitHeight + ClockStyle.gapSmall + ClockStyle.gapLarge
                            radius: ClockStyle.radiusCard
                            color: ClockStyle.colPane

                            ColumnLayout {
                                id: listColumn
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: ClockStyle.gapSmall
                                anchors.topMargin: ClockStyle.gapLarge
                                spacing: 2

                                ListHeader {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: ClockStyle.gapSmall + 2
                                    Layout.rightMargin: ClockStyle.gapTiny
                                    Layout.bottomMargin: ClockStyle.gapSmall
                                }

                                Repeater {
                                    id: rowRepeater
                                    model: ScriptModel {
                                        values: root.ranked
                                        objectProp: "key"
                                    }

                                    delegate: AppRow {
                                        Layout.fillWidth: true
                                    }
                                }

                                ListEmpty {
                                    Layout.fillWidth: true
                                    Layout.topMargin: ClockStyle.gapHuge
                                    Layout.bottomMargin: ClockStyle.gapHuge
                                    visible: root.ranked.length === 0
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Side sheet ──────────────────────────────────────────────────
        Item {
            id: sheetSlot
            Layout.fillHeight: true
            Layout.preferredWidth: sidePanel.open ? root.sheetWidth + (root.compact ? 0 : ClockStyle.paneGap) : 0
            visible: Layout.preferredWidth > 1
            clip: true

            Behavior on Layout.preferredWidth {
                enabled: !ClockStyle.reducedMotion
                animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
            }

            ClockSidePanel {
                id: sidePanel
                anchors {
                    top: parent.top
                    bottom: parent.bottom
                    right: parent.right
                }
                width: root.sheetWidth
            }
        }
    }
}
