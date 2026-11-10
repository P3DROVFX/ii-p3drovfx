pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.usage.limits
import "UsageFormat.js" as Format

/**
 * The Network tab: how much data moved over the period, which apps moved it, and
 * how much of it could not be pinned on any.
 *
 * The sampler reads each TCP socket's own byte counters and the physical interfaces'
 * totals, so the device figure here is what the hardware carried and the per-app
 * rows are the part matched to a process. The gap between the two is shown as its
 * own row rather than spread over the apps: QUIC, connections that came and went
 * between two samples, other users' daemons, and TCP/IP headers all live there, and
 * its size is the honest measure of how far to trust the rest.
 *
 * Same period controls, histogram and day files as the pages beside it; a day draws
 * hours, a week or a month draws days, and any bar or row narrows the page to it.
 */
Item {
    id: root

    // ── Page contract ───────────────────────────────────────────────────
    property bool compact: false
    /// Shared with the shell and the other pages: granularity and periodOffset are
    /// read and written here; metricKey and selectedKey are left alone.
    required property QtObject viewState

    readonly property string pageSubtitle: root.liveRate
        ? Translation.tr("%1 down · %2 up").arg(root.rateText(root.liveRate.rx)).arg(root.rateText(root.liveRate.tx))
        : ""
    readonly property bool detailOpen: false
    readonly property string detailTitle: ""

    function closeDetail(): void {
    }

    function handleEscape(): bool {
        if (root.focusedBucket < 0)
            return false;
        root.focusedBucket = -1;
        return true;
    }

    function handleKey(key: int, modifiers: int): bool {
        if (modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
            return false;
        switch (key) {
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
        // The breakdown runs newest first, so Down walks back in time.
        case Qt.Key_Down:
            root.walkBucket(-1);
            return true;
        case Qt.Key_Up:
            root.walkBucket(1);
            return true;
        }
        return false;
    }

    // ── Layout ──────────────────────────────────────────────────────────
    /// The settled page width (the shell's `pageLayoutWidth`); every layout decision
    /// reads this rather than the live width, so the page re-deals once while the rail
    /// folds instead of reflowing frame by frame.
    property real layoutWidth: root.width

    readonly property bool wide: !root.compact && root.layoutWidth >= 820
    readonly property real heroWidth: root.wide
        ? Math.round(Math.max(380, Math.min(root.layoutWidth - 380, root.layoutWidth * 0.48)))
        : root.layoutWidth
    property real heroWidthShown: root.heroWidth
    Behavior on heroWidthShown {
        enabled: !ClockStyle.reducedMotion
        animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
    }
    readonly property real sideLayoutWidth: root.wide
        ? Math.max(0, root.layoutWidth - root.heroWidth - ClockStyle.paneGap) : root.layoutWidth
    readonly property real heroInset: ClockStyle.cardPadding + 4
    readonly property real heroContentWidth: Math.max(0, root.heroWidth - root.heroInset * 2)

    readonly property int tileColumns: Math.max(1,
        Math.floor((root.sideLayoutWidth + ClockStyle.gap) / (250 + ClockStyle.gap)))
    readonly property real tileLayoutWidth: (root.sideLayoutWidth - ClockStyle.gap * (root.tileColumns - 1))
        / root.tileColumns
    property real tileWidth: root.tileLayoutWidth
    Behavior on tileWidth {
        enabled: !ClockStyle.reducedMotion
        animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
    }

    // ── Period ──────────────────────────────────────────────────────────
    readonly property var granularities: ["day", "week", "month"]
    readonly property string granularity: root.granularities.includes(root.viewState.granularity)
        ? root.viewState.granularity : "day"
    readonly property int granularityIndex: root.granularities.indexOf(root.granularity)
    readonly property int periodOffset: Math.min(0, root.viewState.periodOffset)
    /// The hour or day the figures are narrowed to, or -1 for the whole period.
    property int focusedBucket: -1

    readonly property bool isSingleDay: root.granularity === "day"
    readonly property var dates: AppStats.periodDates(root.granularity, root.periodOffset)
    readonly property bool canGoBack: AppStats.hasEarlierPeriod(root.granularity, root.periodOffset)

    readonly property int nowIndex: {
        if (root.dates.length === 0)
            return -1;
        if (root.isSingleDay)
            return root.periodOffset === 0 ? DateTime.clock.date.getHours() : -1;
        return root.dates[root.dates.length - 1] === AppStats.todayDate ? root.dates.length - 1 : -1;
    }
    readonly property int lastLive: root.isSingleDay && root.nowIndex >= 0 ? root.nowIndex : root.buckets.length - 1

    readonly property int dayStride: Math.max(1, Math.ceil(root.dates.length / 10))

    function stepPeriod(delta: int): void {
        const next = Math.min(0, root.periodOffset + delta);
        if (next === root.periodOffset)
            return;
        if (next < root.periodOffset && !root.canGoBack)
            return;
        root.viewState.periodOffset = next;
        root.focusedBucket = -1;
    }

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

    /// Steps the narrowed bucket through the ones that moved data; from nothing,
    /// starts at the newest.
    function walkBucket(delta: int): void {
        let index = root.focusedBucket < 0 ? (delta < 0 ? root.lastLive + 1 : -1) : root.focusedBucket;
        do {
            index += delta;
        } while (index >= 0 && index <= root.lastLive && (root.bucketBytes[index] ?? 0) <= 0);
        if (index < 0 || index > root.lastLive) {
            root.focusedBucket = -1;
            return;
        }
        root.focusedBucket = index;
    }

    function refresh(): void {
        AppStats.ensureDates(root.dates);
        AppStats.refresh();
    }

    /// A rate in bytes per second, never "—": a quiet second is a real reading.
    function rateText(bytesPerSecond: real): string {
        return bytesPerSecond < 1 ? "0 B/s" : `${Format.bytes(bytesPerSecond)}/s`;
    }

    // ── Figures ─────────────────────────────────────────────────────────
    /// Throughput over the last sample interval: what the interfaces carried, which
    /// is every app's share plus the unattributed remainder. Null until a sampler
    /// that counts data has sent one.
    readonly property var liveRate: {
        const sample = AppStats.lastSample;
        if (!AppStats.trackNetwork || !sample || !(sample.dtMs > 0) || sample.sysRx === undefined)
            return null;
        let rx = sample.sysRx;
        let tx = sample.sysTx;
        for (const app of sample.apps ?? []) {
            rx += app.rx ?? 0;
            tx += app.tx ?? 0;
        }
        return {
            rx: rx * 1000 / sample.dtMs,
            tx: tx * 1000 / sample.dtMs
        };
    }

    readonly property var targetDates: {
        if (root.focusedBucket >= 0 && !root.isSingleDay) {
            const date = root.dates[root.focusedBucket];
            return date ? [date] : root.dates;
        }
        return root.dates;
    }
    readonly property int focusedHour: root.isSingleDay ? root.focusedBucket : -1

    /// `{ rx, tx, matched }` in KiB per hour of the day, or per day of a week or month.
    /// Touching `history` is what makes it recompute when a day file lands.
    readonly property var buckets: {
        AppStats.history;
        if (root.isSingleDay) {
            const date = root.dates[0];
            if (!date)
                return [];
            const hours = AppStats.networkHours(date);
            return hours.rx.map((rx, hour) => ({
                rx: rx,
                tx: hours.tx[hour],
                matched: hours.matched[hour]
            }));
        }
        return AppStats.networkDaily(root.dates);
    }
    /// Both directions per bucket, in bytes, for the chart.
    readonly property var bucketBytes: root.buckets.map(bucket => (bucket.rx + bucket.tx) * 1024)

    /// The period's totals in KiB, or the narrowed bucket's.
    readonly property var rollup: {
        const picked = root.focusedBucket >= 0 ? [root.buckets[root.focusedBucket]] : root.buckets;
        const out = { rx: 0, tx: 0, matched: 0 };
        for (const bucket of picked) {
            if (!bucket)
                continue;
            out.rx += bucket.rx;
            out.tx += bucket.tx;
            out.matched += bucket.matched;
        }
        out.total = out.rx + out.tx;
        return out;
    }
    readonly property real matchedShare: root.rollup.total > 0 ? Math.min(1, root.rollup.matched / root.rollup.total) : NaN

    /// The busiest bucket of the period, for its tile.
    readonly property int peakIndex: {
        let best = -1;
        for (let i = 0; i <= root.lastLive && i < root.bucketBytes.length; i++) {
            if (root.bucketBytes[i] > 0 && (best < 0 || root.bucketBytes[i] > root.bucketBytes[best]))
                best = i;
        }
        return best;
    }

    readonly property var chartLabels: {
        if (root.isSingleDay)
            return Array.from({ length: 24 }, (unused, hour) => Format.hourLabel(hour));
        const first = (root.dates.length - 1) % root.dayStride;
        return root.dates.map((date, index) => Format.dayLabel(date,
            index === first || index === root.dates.length - 1 || date.slice(-2) === "01"));
    }

    readonly property var bucketNames: {
        if (root.isSingleDay)
            return root.chartLabels;
        return root.dates.map(date => new Date(date + "T12:00:00").toLocaleDateString(Qt.locale(), "ddd d MMM"));
    }

    /// The apps over the same span, the hidden services folded into the remainder the
    /// way the summary already folds their energy.
    readonly property var summary: {
        AppStats.history;
        const opts = {
            headless: AppStats.showHeadless
        };
        if (root.focusedHour >= 0) {
            opts.hourFrom = root.focusedHour;
            opts.hourTo = root.focusedHour;
        }
        return AppStats.summarize(root.targetDates, opts);
    }

    readonly property var dataApps: {
        const list = root.summary.apps.map(rec => ({
            key: rec.key,
            headless: rec.headless,
            rx: rec.netRx,
            tx: rec.netTx
        })).filter(entry => entry.rx + entry.tx > 0);
        const system = root.summary.system;
        if (system.netRx + system.netTx > 0)
            list.push({ key: AppStats.systemKey, headless: true, rx: system.netRx, tx: system.netTx });
        list.sort((a, b) => (b.rx + b.tx) - (a.rx + a.tx));
        return list.slice(0, 8);
    }
    readonly property real dataMax: root.dataApps.length > 0 ? root.dataApps[0].rx + root.dataApps[0].tx : 0

    readonly property real appsKib: root.summary.totals.netRx + root.summary.totals.netTx
    readonly property real appsBgKib: root.summary.totals.netBg

    /// The sampler running is one built before it counted data — nothing recorded and
    /// nothing coming until it is rebuilt.
    readonly property bool needsRebuild: AppStats.running && !AppStats.samplerCountsNetwork
    /// Every packet counted in the kernel, against TCP socket counters sampled every
    /// few seconds. The two are different enough to say which one is on screen.
    readonly property bool exact: AppStats.netMode === "exact"
    readonly property bool approximate: AppStats.netMode === "sockets" && !root.needsRebuild

    readonly property var periodTiles: [
        {
            symbol: "download",
            label: Translation.tr("Received"),
            value: Format.bytesFromKib(root.rollup.rx),
            caption: root.rollup.total > 0
                ? Translation.tr("%1 % of the traffic").arg(Math.round(root.rollup.rx / root.rollup.total * 100)) : "",
            shown: true
        },
        {
            symbol: "upload",
            label: Translation.tr("Sent"),
            value: Format.bytesFromKib(root.rollup.tx),
            caption: "",
            shown: true
        },
        {
            symbol: "link",
            label: Translation.tr("Matched to apps"),
            value: isNaN(root.matchedShare) ? "—" : `${Math.round(root.matchedShare * 100)} %`,
            caption: root.rollup.total > root.rollup.matched
                ? Translation.tr("%1 unattributed").arg(Format.bytesFromKib(root.rollup.total - root.rollup.matched)) : "",
            shown: true
        },
        {
            symbol: "visibility_off",
            label: Translation.tr("In the background"),
            value: Format.bytesFromKib(root.appsBgKib),
            caption: root.appsKib > 0 && root.appsBgKib > 0
                ? Translation.tr("%1 % of the apps' data").arg(Math.round(root.appsBgKib / root.appsKib * 100)) : "",
            shown: true
        },
        {
            symbol: "trending_up",
            label: root.isSingleDay ? Translation.tr("Busiest hour") : Translation.tr("Busiest day"),
            value: root.peakIndex >= 0 ? Format.bytes(root.bucketBytes[root.peakIndex]) : "—",
            caption: root.peakIndex >= 0 ? (root.bucketNames[root.peakIndex] ?? "") : "",
            shown: root.focusedBucket < 0
        }
    ].filter(tile => tile.shown)

    onDatesChanged: AppStats.ensureDates(root.dates)
    Component.onCompleted: AppStats.ensureDates(root.dates)

    // ── Pieces ──────────────────────────────────────────────────────────
    /// The period's total in big digits, split by direction, over the period's chart.
    component Hero: Rectangle {
        id: hero

        /// A fixed-height chart for the stacked page instead of one filling the pane.
        property bool stacked: false

        // The same pair as the App usage and Battery heroes: the tabs read as one app.
        readonly property color colPane: ClockStyle.colPrimary
        readonly property color colContent: ClockStyle.colOnPrimary

        readonly property int totalSize: Math.round(Math.max(48, Math.min(112, root.heroContentWidth * 0.2)))
        readonly property int splitSize: Math.round(Math.max(20, Math.min(28, root.heroContentWidth * 0.05)))
        readonly property real rxShare: root.rollup.total > 0 ? root.rollup.rx / root.rollup.total : 0.5

        implicitHeight: heroColumn.implicitHeight + root.heroInset * 2
        radius: ClockStyle.radiusCard
        color: hero.colPane

        ColumnLayout {
            id: heroColumn
            anchors {
                fill: parent
                margins: root.heroInset
            }
            spacing: ClockStyle.gap

            // ── Header ──────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall + 2

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: root.focusedBucket >= 0
                            ? (root.bucketNames[root.focusedBucket] ?? "")
                            : AppStats.periodLabel(root.granularity, root.periodOffset)
                        font.family: ClockStyle.fontTitle
                        font.variableAxes: ClockStyle.axesTitle
                        font.pixelSize: ClockStyle.textTitle
                        color: hero.colContent
                        elide: Text.ElideRight
                    }

                    StyledText {
                        id: heroDetail
                        Layout.fillWidth: true
                        text: {
                            const mode = root.exact ? Translation.tr("Exact") : root.approximate ? Translation.tr("Approximate") : "";
                            const matched = isNaN(root.matchedShare) ? ""
                                : Translation.tr("%1 % matched to an app").arg(Math.round(root.matchedShare * 100));
                            return [mode, matched].filter(part => part.length > 0).join(" · ") || Translation.tr("Data per app");
                        }
                        font.pixelSize: ClockStyle.textNormal
                        font.weight: Font.DemiBold
                        color: hero.colContent
                        opacity: 0.8
                        elide: Text.ElideRight

                        HoverHandler {
                            id: heroDetailHover
                        }
                        StyledToolTip {
                            extraVisibleCondition: heroDetailHover.hovered && heroDetail.truncated
                            text: heroDetail.text
                        }
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

            // ── The total ───────────────────────────────────────────
            UsageFigure {
                Layout.maximumWidth: parent.width
                text: root.rollup.total > 0 ? Format.bytesFromKib(root.rollup.total) : "—"
                size: hero.totalSize
                color: hero.colContent
            }

            // Received against sent as one capsule cut in two: the direction is the
            // only split this figure has, and a ratio reads faster as a length.
            Item {
                id: split
                Layout.fillWidth: true
                implicitHeight: 14

                readonly property real gap: 3
                property real share: hero.rxShare
                Behavior on share {
                    enabled: !ClockStyle.reducedMotion
                    animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: Math.max(split.height, (split.width - split.gap) * split.share)
                    radius: ClockStyle.pill(split.height)
                    color: hero.colContent
                    opacity: root.rollup.total > 0 ? 0.9 : 0.14
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: Math.max(split.height, (split.width - split.gap) * (1 - split.share))
                    radius: ClockStyle.pill(split.height)
                    color: hero.colContent
                    opacity: root.rollup.total > 0 ? 0.35 : 0.14
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapHuge

                Repeater {
                    model: [
                        { symbol: "download", label: Translation.tr("Received"), kib: root.rollup.rx, align: Qt.AlignLeft },
                        { symbol: "upload", label: Translation.tr("Sent"), kib: root.rollup.tx, align: Qt.AlignRight }
                    ]

                    ColumnLayout {
                        id: direction
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 0

                        RowLayout {
                            Layout.alignment: direction.modelData.align
                            spacing: ClockStyle.gapTiny

                            MaterialSymbol {
                                text: direction.modelData.symbol
                                iconSize: ClockStyle.iconSmall - 2
                                fill: 1
                                color: hero.colContent
                                opacity: 0.75
                            }

                            StyledText {
                                text: direction.modelData.label
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.Bold
                                color: hero.colContent
                                opacity: 0.75
                            }
                        }

                        UsageFigure {
                            Layout.alignment: direction.modelData.align
                            text: Format.bytesFromKib(direction.modelData.kib)
                            size: hero.splitSize
                            axes: ClockStyle.axesDigits
                            color: hero.colContent
                        }
                    }
                }
            }

            // ── The period ──────────────────────────────────────────
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

            StyledText {
                Layout.fillWidth: true
                text: root.isSingleDay ? Translation.tr("Data per hour") : Translation.tr("Data per day")
                font.pixelSize: ClockStyle.textSmall
                font.weight: Font.Bold
                color: hero.colContent
                opacity: 0.85
                elide: Text.ElideRight
            }

            UsageHistogram {
                Layout.fillWidth: true
                Layout.fillHeight: !hero.stacked
                Layout.preferredHeight: 150
                Layout.minimumHeight: 120
                values: root.bucketBytes
                labels: root.chartLabels
                tooltipLabels: root.bucketNames
                nowIndex: root.nowIndex
                trimFuture: root.isSingleDay
                focusedIndex: root.focusedBucket
                labelStride: root.isSingleDay ? 4 : root.dayStride
                labelAnchorEnd: !root.isSingleDay
                formatValue: value => Format.bytes(value)
                formatTick: value => Format.bytes(value)
                noteAt: index => {
                    const bucket = root.buckets[index];
                    if (!bucket || bucket.rx + bucket.tx <= 0)
                        return "";
                    return Translation.tr("%1 received · %2 sent")
                        .arg(Format.bytesFromKib(bucket.rx)).arg(Format.bytesFromKib(bucket.tx));
                }
                colContent: hero.colContent
                colPane: hero.colPane
                onBarClicked: index => root.focusBucket(index)
            }
        }
    }

    /// The period's figures as tiles; columns and widths from the settled width.
    component PeriodTiles: Flow {
        id: tiles

        readonly property real flowWidth: Math.max(root.sideLayoutWidth,
            Math.ceil(root.tileWidth * root.tileColumns + ClockStyle.gap * (root.tileColumns - 1)) + 1)

        Layout.preferredWidth: tiles.flowWidth
        Layout.minimumWidth: tiles.flowWidth
        spacing: ClockStyle.gap

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
            model: root.periodTiles

            Rectangle {
                id: periodTile
                required property var modelData
                required property int index
                width: Math.floor(root.tileWidth)
                height: 112
                radius: ClockStyle.radiusCard
                color: ClockStyle.colPane

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: ClockStyle.gapLarge
                    anchors.leftMargin: ClockStyle.cardPadding - 2
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapSmall

                        MaterialShapeWrappedMaterialSymbol {
                            text: periodTile.modelData.symbol
                            iconSize: 16
                            padding: 6
                            shape: MaterialShape.Shape.Clover4Leaf
                            color: ClockStyle.colSecondaryContainer
                            colSymbol: ClockStyle.colOnSecondaryContainer
                            fill: 1
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: periodTile.modelData.label
                            font.pixelSize: ClockStyle.textSmall
                            font.weight: Font.DemiBold
                            color: ClockStyle.colOnSurfaceVariant
                            elide: Text.ElideRight
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                    }

                    UsageFigure {
                        Layout.maximumWidth: parent.width
                        text: periodTile.modelData.value
                        size: 30
                        color: ClockStyle.colOnSurface
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: periodTile.modelData.caption.length > 0
                        text: periodTile.modelData.caption
                        font.pixelSize: ClockStyle.textSmall
                        color: ClockStyle.colSubtext
                        elide: Text.ElideRight
                    }
                }

                StaggeredEntrance {
                    index: periodTile.index
                    step: ClockStyle.staggerStep
                    active: !ClockStyle.reducedMotion
                }
            }
        }
    }

    component SectionTitle: ColumnLayout {
        id: section
        property string title: ""
        property string subtitle: ""
        spacing: 0

        StyledText {
            Layout.fillWidth: true
            text: section.title
            font.family: ClockStyle.fontTitle
            font.variableAxes: ClockStyle.axesTitle
            font.pixelSize: ClockStyle.textLarge + 2
            color: ClockStyle.colOnSurface
            elide: Text.ElideRight
        }

        StyledText {
            Layout.fillWidth: true
            visible: section.subtitle.length > 0
            text: section.subtitle
            font.pixelSize: ClockStyle.textSmall
            color: ClockStyle.colSubtext
            wrapMode: Text.WordWrap
        }
    }

    /// On the socket counters, what is missing and the one command that fixes it.
    component ExactCard: Rectangle {
        implicitHeight: exactColumn.implicitHeight + ClockStyle.cardPadding * 2
        radius: ClockStyle.radiusCard
        color: ClockStyle.colPane
        visible: root.approximate

        ColumnLayout {
            id: exactColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: ClockStyle.cardPadding
            spacing: ClockStyle.gap

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gap

                MaterialShapeWrappedMaterialSymbol {
                    text: "troubleshoot"
                    iconSize: 20
                    padding: 10
                    shape: MaterialShape.Shape.Cookie9Sided
                    color: ClockStyle.colTertiaryContainer
                    colSymbol: ClockStyle.colOnTertiaryContainer
                    fill: 1
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: AppStats.netHelperInstalled ? Translation.tr("The exact counter could not start")
                            : Translation.tr("These figures are approximate")
                        font.pixelSize: ClockStyle.textNormal + 1
                        font.weight: Font.Bold
                        color: ClockStyle.colOnSurface
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: AppStats.netHelperInstalled && AppStats.netError.length > 0
                            ? Translation.tr("%1. Reinstall it with the command below.").arg(AppStats.netError)
                            : Translation.tr("Only TCP connections that stay open across a sample are matched to an app, so QUIC and short requests land in Unattributed. A small kernel helper counts every packet instead; installing it asks for your password once.")
                        wrapMode: Text.WordWrap
                        font.pixelSize: ClockStyle.textSmall
                        color: ClockStyle.colSubtext
                    }
                }
            }

            UsageCodeSnippet {
                Layout.fillWidth: true
                snippet: AppStats.netHelperScript.replace(FileUtils.trimFileProtocol(Directories.home), "~")
            }
        }
    }

    /// The apps the period's data went to, and the part no app could be credited with.
    component AppsPane: Rectangle {
        implicitHeight: appsColumn.implicitHeight + ClockStyle.cardPadding * 2
        radius: ClockStyle.radiusCard
        color: ClockStyle.colPane

        ColumnLayout {
            id: appsColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: ClockStyle.cardPadding
            spacing: ClockStyle.gap

            SectionTitle {
                Layout.fillWidth: true
                title: Translation.tr("Where the data went")
                subtitle: root.exact
                    ? Translation.tr("Every packet counted in the kernel and credited to the process that owned its socket, or to the app that started it once it has exited. Unattributed is traffic of no socket at all (ARP, DHCP, ICMP) and link-layer framing.")
                    : Translation.tr("TCP traffic matched to the process that held the connection. Unattributed is everything else the network cards carried: QUIC, connections shorter than one sample, other users' services and packet headers.")
            }

            Repeater {
                model: root.dataApps

                RowLayout {
                    id: appRow
                    required property var modelData
                    readonly property bool isSystem: appRow.modelData.key === AppStats.systemKey
                    readonly property real total: appRow.modelData.rx + appRow.modelData.tx
                    Layout.fillWidth: true
                    spacing: ClockStyle.gap

                    Rectangle {
                        implicitWidth: 40
                        implicitHeight: 40
                        radius: ClockStyle.pill(40)
                        color: ClockStyle.colSurfaceHigh

                        LimitsAppIcon {
                            anchors.centerIn: parent
                            size: 26
                            appKey: appRow.isSystem ? "" : appRow.modelData.key
                            fallbackSymbol: appRow.isSystem ? "lan" : appRow.modelData.headless ? "terminal" : "apps"
                            colFallback: ClockStyle.colOnSurfaceVariant
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapTiny + 2

                        StyledText {
                            id: appName
                            Layout.fillWidth: true
                            text: appRow.isSystem ? Translation.tr("Unattributed") : AppStats.displayName(appRow.modelData.key)
                            font.pixelSize: ClockStyle.textNormal
                            font.weight: Font.DemiBold
                            color: ClockStyle.colOnSurface
                            elide: Text.ElideRight

                            HoverHandler {
                                id: appNameHover
                            }
                            StyledToolTip {
                                extraVisibleCondition: appNameHover.hovered && appName.truncated
                                text: appName.text
                            }
                        }

                        // The row's share of the busiest row; the received part solid,
                        // the sent part a lighter run after it.
                        Rectangle {
                            id: track
                            Layout.fillWidth: true
                            implicitHeight: 6
                            radius: Appearance.rounding.verysmall
                            color: ClockStyle.colSurfaceHigh

                            readonly property real filled: Math.max(track.height,
                                track.width * (root.dataMax > 0 ? appRow.total / root.dataMax : 0))
                            readonly property color colBar: appRow.isSystem ? ClockStyle.colSubtext : ClockStyle.colPrimary

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: track.filled
                                radius: parent.radius
                                color: track.colBar
                                opacity: 0.4

                                Behavior on width {
                                    enabled: !ClockStyle.reducedMotion
                                    animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                                }
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: appRow.total > 0 ? Math.max(track.height, track.filled * appRow.modelData.rx / appRow.total) : 0
                                radius: parent.radius
                                color: track.colBar

                                Behavior on width {
                                    enabled: !ClockStyle.reducedMotion
                                    animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.minimumWidth: 84
                        spacing: -2

                        StyledText {
                            Layout.alignment: Qt.AlignRight
                            text: Format.bytesFromKib(appRow.total)
                            font.family: ClockStyle.fontMain
                            font.variableAxes: ClockStyle.axesDigitsBold
                            font.pixelSize: 20
                            color: ClockStyle.colOnSurface
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignRight
                            text: Translation.tr("↓ %1 · ↑ %2")
                                .arg(Format.bytesFromKib(appRow.modelData.rx)).arg(Format.bytesFromKib(appRow.modelData.tx))
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.Bold
                            color: ClockStyle.colOnSurfaceVariant
                            opacity: 0.8
                        }
                    }
                }
            }

            Loader {
                Layout.fillWidth: true
                Layout.topMargin: ClockStyle.gapSmall
                Layout.bottomMargin: ClockStyle.gapSmall
                active: root.dataApps.length === 0 && !root.needsRebuild
                visible: active
                sourceComponent: ClockEmptyState {
                    symbol: "wifi_off"
                    shape: "Pill"
                    shapeSize: 72
                    title: Translation.tr("No data recorded")
                    subtitle: Translation.tr("Nothing moved over the network in this period, or the sampler was not running. Try another one.")
                }
            }

            // A sampler built before it counted data reports none, whatever the traffic.
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.needsRebuild
                spacing: ClockStyle.gap

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gap

                    MaterialShapeWrappedMaterialSymbol {
                        text: "build"
                        iconSize: 20
                        padding: 10
                        shape: MaterialShape.Shape.Pentagon
                        color: ClockStyle.colTertiaryContainer
                        colSymbol: ClockStyle.colOnTertiaryContainer
                        fill: 1
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("The sampler does not count data yet")
                            font.pixelSize: ClockStyle.textNormal + 1
                            font.weight: Font.Bold
                            color: ClockStyle.colOnSurface
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("The one running was built before it learned to. Rebuild it; the shell picks the new binary up when this app is next opened.")
                            wrapMode: Text.WordWrap
                            font.pixelSize: ClockStyle.textSmall
                            color: ClockStyle.colSubtext
                        }
                    }
                }

                UsageCodeSnippet {
                    Layout.fillWidth: true
                    snippet: Directories.rustHelpersScriptPath.replace(FileUtils.trimFileProtocol(Directories.home), "~")
                        + " build app_stats"
                }
            }
        }
    }

    /// Hour by hour or day by day, newest first; a row narrows the page to its bucket.
    component BreakdownPane: Rectangle {
        implicitHeight: breakdownColumn.implicitHeight + ClockStyle.cardPadding + ClockStyle.gapSmall
        radius: ClockStyle.radiusCard
        color: ClockStyle.colPane
        visible: root.peakIndex >= 0

        ColumnLayout {
            id: breakdownColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: ClockStyle.gapSmall
            anchors.topMargin: ClockStyle.cardPadding
            spacing: 2

            SectionTitle {
                Layout.fillWidth: true
                Layout.leftMargin: ClockStyle.gap
                Layout.bottomMargin: ClockStyle.gapSmall
                title: root.isSingleDay ? Translation.tr("Hour by hour") : Translation.tr("Day by day")
                subtitle: Translation.tr("Received · sent · share matched to an app")
            }

            Repeater {
                model: root.lastLive + 1

                Rectangle {
                    id: bucketRow
                    required property int index
                    readonly property int bucketIndex: root.lastLive - bucketRow.index
                    readonly property var bucket: root.buckets[bucketRow.bucketIndex] ?? null
                    readonly property real total: bucketRow.bucket ? bucketRow.bucket.rx + bucketRow.bucket.tx : 0
                    readonly property bool uploadHeavy: bucketRow.bucket !== null && bucketRow.bucket.tx > bucketRow.bucket.rx
                    readonly property bool focused: root.focusedBucket === bucketRow.bucketIndex

                    Layout.fillWidth: true
                    visible: bucketRow.total > 0
                    implicitHeight: 62
                    radius: bucketRow.focused ? ClockStyle.radiusLarge : ClockStyle.radiusNormal
                    color: bucketRow.focused ? ClockStyle.colSecondaryContainer
                        : bucketHover.hovered ? ClockStyle.colIdleCardHover : "transparent"

                    Behavior on color {
                        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
                    }

                    HoverHandler {
                        id: bucketHover
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.focusBucket(bucketRow.bucketIndex)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: ClockStyle.gapSmall + 2
                        anchors.rightMargin: ClockStyle.gap
                        spacing: ClockStyle.gap

                        MaterialShapeWrappedMaterialSymbol {
                            text: bucketRow.uploadHeavy ? "upload" : "download"
                            iconSize: 18
                            padding: 8
                            shape: bucketRow.uploadHeavy ? MaterialShape.Shape.Sunny : MaterialShape.Shape.Cookie6Sided
                            color: bucketRow.focused ? ClockStyle.colSecondaryContainerHover
                                : bucketRow.uploadHeavy ? ClockStyle.colTertiaryContainer : ClockStyle.colSurfaceHigh
                            colSymbol: bucketRow.focused ? ClockStyle.colOnSecondaryContainer
                                : bucketRow.uploadHeavy ? ClockStyle.colOnTertiaryContainer : ClockStyle.colOnSurfaceVariant
                            fill: 1
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                id: bucketName
                                Layout.fillWidth: true
                                text: root.bucketNames[bucketRow.bucketIndex] ?? ""
                                font.pixelSize: ClockStyle.textNormal
                                font.weight: Font.DemiBold
                                color: bucketRow.focused ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: {
                                    const bucket = bucketRow.bucket;
                                    if (!bucket)
                                        return "";
                                    const matched = bucketRow.total > 0
                                        ? Translation.tr("%1 % matched").arg(Math.round(Math.min(1, bucket.matched / bucketRow.total) * 100)) : "";
                                    return [
                                        Translation.tr("↓ %1").arg(Format.bytesFromKib(bucket.rx)),
                                        Translation.tr("↑ %1").arg(Format.bytesFromKib(bucket.tx)),
                                        matched
                                    ].filter(part => part.length > 0).join(" · ");
                                }
                                font.pixelSize: ClockStyle.textSmall
                                color: bucketRow.focused ? ClockStyle.colOnSecondaryContainer : ClockStyle.colSubtext
                                opacity: bucketRow.focused ? 0.85 : 1
                                elide: Text.ElideRight
                            }
                        }

                        UsageFigure {
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            text: Format.bytesFromKib(bucketRow.total)
                            size: 22
                            color: bucketRow.focused ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface
                        }
                    }
                }
            }
        }
    }

    // ── Recording off ───────────────────────────────────────────────────
    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - ClockStyle.gapHuge * 2, 380)
        visible: !AppStats.trackNetwork
        spacing: ClockStyle.gapLarge

        ClockEmptyState {
            Layout.fillWidth: true
            shape: "Cookie12Sided"
            symbol: "signal_disconnected"
            title: Translation.tr("Network data is off")
            subtitle: Translation.tr("Turn it on to see which apps use the network. It reads the kernel's own counters and needs no extra permission.")
        }

        LimitsTintButton {
            Layout.alignment: Qt.AlignHCenter
            symbol: "swap_vert"
            label: Translation.tr("Record network data")
            solid: true
            colContent: ClockStyle.colPrimary
            colSolidContent: ClockStyle.colOnPrimary
            onClicked: Config.options.appStats.trackNetwork = true
        }
    }

    // Wide: the total and its chart on the left at full height, the rest beside it.
    Loader {
        anchors.fill: parent
        active: AppStats.trackNetwork && root.wide
        visible: active
        sourceComponent: RowLayout {
            spacing: ClockStyle.paneGap

            Hero {
                Layout.preferredWidth: root.heroWidthShown
                Layout.fillHeight: true
            }

            StyledFlickable {
                id: sideFlick
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: sideColumn.implicitHeight + ClockStyle.gapHuge
                clip: true

                ColumnLayout {
                    id: sideColumn
                    width: sideFlick.width
                    spacing: ClockStyle.paneGap

                    PeriodTiles {}

                    ExactCard {
                        Layout.fillWidth: true
                    }

                    AppsPane {
                        Layout.fillWidth: true
                    }

                    BreakdownPane {
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }

    // Narrow: one scrolling column, the total first.
    Loader {
        anchors.fill: parent
        active: AppStats.trackNetwork && !root.wide
        visible: active
        sourceComponent: StyledFlickable {
            id: narrowFlick
            contentWidth: width
            contentHeight: narrowColumn.implicitHeight + ClockStyle.gapHuge
            clip: true

            ColumnLayout {
                id: narrowColumn
                width: narrowFlick.width
                spacing: ClockStyle.paneGap

                Hero {
                    Layout.fillWidth: true
                    stacked: true
                }

                PeriodTiles {}

                ExactCard {
                    Layout.fillWidth: true
                }

                AppsPane {
                    Layout.fillWidth: true
                }

                BreakdownPane {
                    Layout.fillWidth: true
                }
            }
        }
    }
}
