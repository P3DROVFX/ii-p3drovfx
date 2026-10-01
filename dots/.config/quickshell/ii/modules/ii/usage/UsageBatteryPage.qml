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
 * The Battery tab: where the charge stands now, where it stood over the period, and
 * what it cost to get there.
 *
 * Built on the same day files as App usage — the sampler records the pack beside the
 * apps — so the period controls and the histogram are the ones next door. A day draws
 * the level at the close of each hour, a week or a month the charge spent per day,
 * because a level cannot be summed but watt-hours can.
 *
 * The hero is the pack: the level in a ring, the estimate, its health, and the period
 * chart. Beside it (or under it) the period's figures, the apps the energy went to, and
 * the hour-by-hour or day-by-day breakdown, any row of which narrows the page to it.
 */
Item {
    id: root

    // ── Page contract ───────────────────────────────────────────────────
    property bool compact: false
    /// Shared with the shell and the App usage page: granularity and periodOffset are
    /// read and written here; metricKey and selectedKey are left alone.
    required property QtObject viewState

    readonly property string pageSubtitle: Battery.available ? `${Battery.percent} % · ${root.stateText}` : ""
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
    readonly property bool wide: !root.compact && root.width >= 820
    readonly property real heroWidth: root.wide
        ? Math.round(Math.max(380, Math.min(root.width - 380, root.width * 0.48)))
        : root.width

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

    /// Which bucket is now, or -1 in a period that is already over.
    readonly property int nowIndex: {
        if (root.dates.length === 0)
            return -1;
        if (root.isSingleDay)
            return root.periodOffset === 0 ? DateTime.clock.date.getHours() : -1;
        return root.dates[root.dates.length - 1] === AppStats.todayDate ? root.dates.length - 1 : -1;
    }
    /// The last bucket that has happened.
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

    /// Steps the narrowed bucket through the ones that hold anything; from nothing,
    /// starts at the newest.
    function walkBucket(delta: int): void {
        let index = root.focusedBucket < 0 ? (delta < 0 ? root.lastLive + 1 : -1) : root.focusedBucket;
        do {
            index += delta;
        } while (index >= 0 && index <= root.lastLive && !root.buckets[index]);
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

    // ── Figures ─────────────────────────────────────────────────────────
    /// The dates the figures cover: the whole period, or the one day picked out of it.
    readonly property var targetDates: {
        if (root.focusedBucket >= 0 && !root.isSingleDay) {
            const date = root.dates[root.focusedBucket];
            return date ? [date] : root.dates;
        }
        return root.dates;
    }
    readonly property int focusedHour: root.isSingleDay ? root.focusedBucket : -1

    /// Touching `history` is what makes every figure recompute when a day file lands;
    /// `dates` alone does not change when the data does.
    readonly property var rollup: {
        AppStats.history;
        const opts = {};
        if (root.focusedHour >= 0) {
            opts.hourFrom = root.focusedHour;
            opts.hourTo = root.focusedHour;
        }
        return AppStats.batteryRollup(root.targetDates, opts);
    }

    /// Per-bucket rollups: one per hour of a day, or one per day of a week or month.
    readonly property var buckets: {
        AppStats.history;
        if (root.isSingleDay) {
            const date = root.dates[0];
            return date ? AppStats.batteryHours(date) : [];
        }
        // A day's rollup carries the same figures under other names — where it left the
        // pack is `last` rather than `end` — so it is renamed into the shape of an hour
        // and everything downstream reads one bucket. A day that recorded nothing
        // becomes null for the same reason an unrecorded hour is one.
        return AppStats.batteryDaily(root.dates).map(day => day.hours === 0 ? null : ({
            end: day.last,
            low: day.low,
            high: day.high,
            outMwh: day.outMwh,
            inMwh: day.inMwh,
            offAc: day.offAc,
            charging: day.charging,
            onAc: day.onAc
        }));
    }

    /// Level at the close of each hour, 0 where the hour holds nothing. Only the day
    /// view has one: a week of levels is a sawtooth of overnight charges that says
    /// nothing a daily total does not say better.
    readonly property var levels: root.isSingleDay ? root.buckets.map(bucket => bucket ? bucket.end : 0) : []

    /// What the pack was doing in each bucket, by whichever of the three it spent most
    /// of it in.
    readonly property var bucketStates: root.buckets.map(bucket => {
        if (!bucket)
            return "";
        if (bucket.charging >= bucket.offAc && bucket.charging >= bucket.onAc)
            return "charge";
        return bucket.offAc >= bucket.onAc ? "off" : "ac";
    })

    /// Milliwatt-hours out of the pack per bucket, for the week and month bars.
    readonly property var dischargeValues: root.buckets.map(bucket => bucket ? bucket.outMwh : 0)
    readonly property real maxOut: Math.max(0, ...root.dischargeValues)

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

    readonly property real fullMwh: root.rollup.fullMwh

    /// Discharge as a share of a full pack, which is the figure that survives being
    /// compared between machines — 12 Wh means nothing without the capacity.
    readonly property real dischargedPercent: root.fullMwh > 0 ? root.rollup.outMwh / root.fullMwh * 100 : NaN

    /// Mean draw while actually running off the pack, in watts. Time plugged in is
    /// excluded, or a day spent mostly on AC would report a machine that sips.
    readonly property real averageWatts: root.rollup.offAc > 0
        ? root.rollup.outMwh / 1000 / (root.rollup.offAc / 3600) : NaN

    /// How long a full charge lasts at that draw: this period's own behaviour rather
    /// than the firmware's guess, so it answers "at this rate".
    readonly property real runtimeHours: !isNaN(root.averageWatts) && root.averageWatts > 0 && root.fullMwh > 0
        ? root.fullMwh / 1000 / root.averageWatts : NaN

    /// Nothing recorded for a period that is still running means the sampler is not
    /// writing it — almost always a binary built before it knew about batteries.
    readonly property bool needsRebuild: root.rollup.hours === 0 && root.periodOffset === 0

    /// Where the energy went over the same span, biggest first: the apps' modelled
    /// share and the remainder that belongs to none of them.
    readonly property var energyApps: {
        AppStats.history;
        const opts = {
            headless: AppStats.showHeadless
        };
        if (root.focusedHour >= 0) {
            opts.hourFrom = root.focusedHour;
            opts.hourTo = root.focusedHour;
        }
        const summary = AppStats.summarize(root.targetDates, opts);
        const list = summary.apps.map(rec => ({
            key: rec.key,
            headless: rec.headless,
            mj: rec.mjFg + rec.mjBg
        })).filter(entry => entry.mj > 0);
        const system = summary.system.mjFg + summary.system.mjBg;
        if (system > 0)
            list.push({ key: AppStats.systemKey, headless: true, mj: system });
        list.sort((a, b) => b.mj - a.mj);
        return list.slice(0, 6);
    }
    readonly property real energyMax: root.energyApps.length > 0 ? root.energyApps[0].mj : 0

    readonly property var periodTiles: [
        {
            symbol: "battery_alert",
            label: Translation.tr("Discharged"),
            value: root.rollup.outMwh > 0 ? Format.energy(root.rollup.outMwh / 1000) : "—",
            caption: isNaN(root.dischargedPercent) || root.dischargedPercent <= 0 ? ""
                : Translation.tr("%1 % of a full charge")
                    .arg(root.dischargedPercent.toFixed(root.dischargedPercent < 10 ? 1 : 0)),
            shown: true
        },
        {
            symbol: "bolt",
            label: Translation.tr("Average draw"),
            value: isNaN(root.averageWatts) ? "—" : `${root.averageWatts.toFixed(1)} W`,
            caption: isNaN(root.runtimeHours) ? ""
                : Translation.tr("about %1 from full").arg(Format.duration(root.runtimeHours * 3600)),
            shown: true
        },
        {
            symbol: "battery_horiz_050",
            label: Translation.tr("On battery"),
            value: Format.duration(root.rollup.offAc),
            caption: "",
            shown: true
        },
        {
            symbol: "battery_charging_full",
            label: Translation.tr("Charging"),
            value: Format.duration(root.rollup.charging),
            caption: root.rollup.inMwh > 0 ? Translation.tr("%1 in").arg(Format.energy(root.rollup.inMwh / 1000)) : "",
            shown: true
        },
        {
            symbol: "power",
            label: Translation.tr("Plugged in, idle"),
            value: Format.duration(root.rollup.onAc),
            caption: "",
            shown: true
        },
        {
            symbol: "trending_down",
            label: Translation.tr("Lowest level"),
            value: isNaN(root.rollup.low) ? "—" : `${Math.round(root.rollup.low)} %`,
            caption: isNaN(root.rollup.high) ? "" : Translation.tr("peaked at %1 %").arg(Math.round(root.rollup.high)),
            shown: !isNaN(root.rollup.low)
        }
    ].filter(tile => tile.shown)

    // ── The pack now ────────────────────────────────────────────────────
    readonly property bool lowUnplugged: Battery.isLowAndUnplugged
    readonly property string stateText: {
        if (Battery.isCharging)
            return Translation.tr("Charging");
        if (Battery.chargeLimitReached)
            return Translation.tr("Held at %1 %").arg(Battery.chargeLimit);
        if (Battery.isFullyCharged)
            return Translation.tr("Fully charged");
        return Battery.isPluggedIn ? Translation.tr("Plugged in") : Translation.tr("On battery");
    }
    /// UPower's estimate, where it has one worth showing.
    readonly property string estimateText: {
        if (Battery.isFullyCharged || Battery.chargeLimitReached || Math.abs(Battery.energyRate) <= 0.01)
            return "";
        if (Battery.isCharging) {
            const toFull = Battery.timeToFullEffective;
            if (toFull <= 0)
                return "";
            return Battery.chargeLimitActive
                ? Translation.tr("%1 to %2 %").arg(Format.duration(toFull)).arg(Battery.chargeLimit)
                : Translation.tr("Full in %1").arg(Format.duration(toFull));
        }
        if (Battery.isPluggedIn || Battery.timeToEmpty <= 0)
            return "";
        return Translation.tr("%1 left").arg(Format.duration(Battery.timeToEmpty));
    }
    readonly property string batterySymbol: {
        if (Battery.isCharging)
            return "battery_charging_full";
        if (Battery.isPluggedIn)
            return "power";
        const step = Math.max(0, Math.min(6, Math.round(Battery.percentage * 6)));
        return step >= 6 ? "battery_full" : `battery_${step}_bar`;
    }

    onDatesChanged: AppStats.ensureDates(root.dates)
    // The shell asks the sampler for a fresh flush once the window has opened.
    Component.onCompleted: AppStats.ensureDates(root.dates)

    // ── Pieces ──────────────────────────────────────────────────────────
    /// The pack: level ring, estimate, health, and the period's chart.
    component Hero: Rectangle {
        id: hero

        /// Ring beside the status rather than above it, for the stacked page.
        property bool stacked: false

        readonly property color colPane: root.lowUnplugged ? ClockStyle.colErrorContainer
            : Battery.isCharging ? ClockStyle.colTertiary : ClockStyle.colPrimary
        readonly property color colContent: root.lowUnplugged ? ClockStyle.colOnErrorContainer
            : Battery.isCharging ? ClockStyle.colOnTertiary : ClockStyle.colOnPrimary
        readonly property real figureSize: Math.round(Math.max(40, Math.min(84, ringArea.ringSize * 0.3)))

        implicitHeight: heroColumn.implicitHeight + (ClockStyle.cardPadding + 4) * 2
        radius: ClockStyle.radiusCard
        color: hero.colPane

        Behavior on color {
            animation: ClockStyle.motionFast.colorAnimation.createObject(this)
        }

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
                    text: root.batterySymbol
                    iconSize: 20
                    padding: 10
                    shape: MaterialShape.Shape.Cookie7Sided
                    color: hero.colContent
                    colSymbol: hero.colPane
                    fill: 1
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: root.stateText
                        font.pixelSize: ClockStyle.textNormal + 1
                        font.weight: Font.DemiBold
                        color: hero.colContent
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Math.abs(Battery.energyRate) > 0.01
                            ? Translation.tr("%1 W right now").arg(Math.abs(Battery.energyRate).toFixed(1))
                            : Translation.tr("Battery")
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

            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: !hero.stacked
                columns: hero.stacked ? 2 : 1
                columnSpacing: ClockStyle.gapHuge
                rowSpacing: ClockStyle.gap

                // ── Ring ────────────────────────────────────────────
                Item {
                    id: ringArea
                    Layout.fillWidth: !hero.stacked
                    Layout.fillHeight: !hero.stacked
                    Layout.preferredWidth: hero.stacked ? 170 : -1
                    Layout.preferredHeight: hero.stacked ? 170 : 200
                    Layout.minimumHeight: 140

                    readonly property real ringSize: Math.round(Math.min(width, height))

                    ClockProgressRing {
                        anchors.centerIn: parent
                        width: ringArea.ringSize
                        height: ringArea.ringSize
                        thickness: Math.max(10, Math.round(ringArea.ringSize * 0.055))
                        value: Battery.percentage
                        wavy: Battery.isCharging
                        waves: 12
                        // Travels only while it charges and the window is up.
                        animateWave: Battery.isCharging && (hero.Window.window?.visible ?? false)
                        colIndicator: hero.colContent
                        colTrack: ColorUtils.applyAlpha(hero.colContent, 0.18)
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: ringArea.ringSize * 0.7
                        spacing: 0

                        UsageFigure {
                            Layout.alignment: Qt.AlignHCenter
                            text: `${Battery.percent} %`
                            size: hero.figureSize
                            color: hero.colContent
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.maximumWidth: parent.width
                            visible: root.estimateText.length > 0
                            text: root.estimateText
                            font.pixelSize: ClockStyle.textNormal
                            font.weight: Font.DemiBold
                            color: hero.colContent
                            opacity: 0.85
                            elide: Text.ElideRight
                        }
                    }
                }

                // ── Facts about the pack ────────────────────────────
                GridLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    columns: hero.stacked ? 1 : 3
                    columnSpacing: ClockStyle.gapSmall
                    rowSpacing: ClockStyle.gapSmall

                    Repeater {
                        model: [
                            {
                                symbol: "health_metrics",
                                label: Battery.cycles >= 0
                                    ? Translation.tr("Health · %1 cycles").arg(Battery.cycles) : Translation.tr("Health"),
                                value: `${Math.round(Battery.health)} %`,
                                shown: Battery.health > 0
                            },
                            {
                                symbol: "battery_profile",
                                label: Battery.chargeLimitActive
                                    ? Translation.tr("Capacity · stops at %1 %").arg(Battery.chargeLimit)
                                    : Translation.tr("Capacity"),
                                value: Format.energy(root.fullMwh / 1000),
                                shown: root.fullMwh > 0
                            },
                            {
                                symbol: "electric_bolt",
                                label: Translation.tr("Average draw"),
                                value: isNaN(root.averageWatts) ? "—" : `${root.averageWatts.toFixed(1)} W`,
                                shown: !isNaN(root.averageWatts)
                            }
                        ].filter(fact => fact.shown)

                        Rectangle {
                            id: factTile
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: 64
                            radius: ClockStyle.radiusNormal
                            color: ColorUtils.applyAlpha(hero.colContent, 0.1)

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.leftMargin: ClockStyle.gapLarge
                                anchors.rightMargin: ClockStyle.gapSmall
                                anchors.topMargin: ClockStyle.gapSmall
                                anchors.bottomMargin: ClockStyle.gapSmall
                                spacing: -2

                                UsageFigure {
                                    text: factTile.modelData.value
                                    size: 24
                                    color: hero.colContent
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: ClockStyle.gapTiny

                                    MaterialSymbol {
                                        text: factTile.modelData.symbol
                                        iconSize: ClockStyle.iconSmall - 2
                                        color: hero.colContent
                                        opacity: 0.8
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: factTile.modelData.label
                                        font.pixelSize: ClockStyle.textSmall
                                        font.weight: Font.DemiBold
                                        color: hero.colContent
                                        opacity: 0.85
                                        elide: Text.ElideRight
                                    }
                                }
                            }
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
                text: (root.isSingleDay ? Translation.tr("Charge level") : Translation.tr("Discharged per day"))
                    + (root.focusedBucket >= 0 ? " · " + (root.bucketNames[root.focusedBucket] ?? "") : "")
                font.pixelSize: ClockStyle.textSmall
                font.weight: Font.Bold
                color: hero.colContent
                opacity: 0.85
                elide: Text.ElideRight
            }

            UsageHistogram {
                Layout.fillWidth: true
                Layout.preferredHeight: 150
                Layout.minimumHeight: 120
                values: root.isSingleDay ? root.levels : root.dischargeValues
                labels: root.chartLabels
                tooltipLabels: root.bucketNames
                nowIndex: root.nowIndex
                trimFuture: root.isSingleDay
                focusedIndex: root.focusedBucket
                labelStride: root.isSingleDay ? 4 : root.dayStride
                labelAnchorEnd: !root.isSingleDay
                // A level is a share of a whole pack, so the axis is the pack rather
                // than the fullest hour on screen: half the height is half a battery.
                axisCeiling: root.isSingleDay ? 100 : 0
                // Milliwatt-hours per watt-hour, the figure the axis is labelled in.
                valueUnit: 1000
                formatValue: value => root.isSingleDay ? `${Math.round(value)} %` : Format.energy(value / 1000)
                formatTick: value => root.isSingleDay ? `${Math.round(value)} %` : Format.energy(value / 1000)
                // A night on the charger should not look like an evening spent draining
                // the pack, however similar the levels.
                emphasisAt: index => {
                    if (!root.isSingleDay)
                        return 0.6;
                    const state = root.bucketStates[index] ?? "";
                    return state === "charge" ? 0.45 : state === "ac" ? 0.25 : 0.7;
                }
                noteAt: index => {
                    const state = root.bucketStates[index] ?? "";
                    return state === "charge" ? Translation.tr("charging")
                        : state === "ac" ? Translation.tr("plugged in")
                        : state === "off" ? Translation.tr("on battery") : "";
                }
                colContent: hero.colContent
                colPane: hero.colPane
                onBarClicked: index => root.focusBucket(index)
            }

            // What the three tints of the day chart mean.
            RowLayout {
                visible: root.isSingleDay
                spacing: ClockStyle.gap

                Repeater {
                    model: [
                        { alpha: 0.7, label: Translation.tr("On battery") },
                        { alpha: 0.45, label: Translation.tr("Charging") },
                        { alpha: 0.25, label: Translation.tr("Plugged in") }
                    ]

                    RowLayout {
                        id: legendItem
                        required property var modelData
                        spacing: ClockStyle.gapTiny + 2

                        Rectangle {
                            implicitWidth: 10
                            implicitHeight: 10
                            radius: 3
                            color: ColorUtils.applyAlpha(hero.colContent, legendItem.modelData.alpha)
                        }

                        StyledText {
                            text: legendItem.modelData.label
                            font.pixelSize: ClockStyle.textSmall
                            color: hero.colContent
                            opacity: 0.8
                        }
                    }
                }
            }
        }
    }

    /// The period's figures as expressive tiles.
    component PeriodTiles: Flow {
        id: tiles
        readonly property int columns: Math.max(1, Math.floor((tiles.width + ClockStyle.gap) / (190 + ClockStyle.gap)))
        readonly property real tileWidth: Math.floor((tiles.width - ClockStyle.gap * (tiles.columns - 1)) / tiles.columns)

        spacing: ClockStyle.gap

        Repeater {
            model: root.periodTiles

            Rectangle {
                id: periodTile
                required property var modelData
                required property int index
                width: tiles.tileWidth
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
                            shape: MaterialShape.Shape.Cookie6Sided
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
            elide: Text.ElideRight
        }
    }

    /// The apps the period's energy went to.
    component EnergyPane: Rectangle {
        implicitHeight: energyColumn.implicitHeight + ClockStyle.cardPadding * 2
        radius: ClockStyle.radiusCard
        color: ClockStyle.colPane

        ColumnLayout {
            id: energyColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: ClockStyle.cardPadding
            spacing: ClockStyle.gap

            SectionTitle {
                Layout.fillWidth: true
                title: Translation.tr("Where the energy went")
                subtitle: {
                    switch (AppStats.source) {
                    case "rapl":
                        return Translation.tr("Modelled per app from RAPL counters, plugged in or not");
                    case "battery":
                        return Translation.tr("Estimated from battery drain, so nothing while plugged in");
                    default:
                        return Translation.tr("Modelled per app from CPU, GPU and memory shares");
                    }
                }
            }

            Repeater {
                model: root.energyApps

                RowLayout {
                    id: energyRow
                    required property var modelData
                    readonly property bool isSystem: energyRow.modelData.key === AppStats.systemKey
                    Layout.fillWidth: true
                    spacing: ClockStyle.gap

                    Rectangle {
                        implicitWidth: 40
                        implicitHeight: 40
                        radius: 20
                        color: ClockStyle.colSurfaceHigh

                        LimitsAppIcon {
                            anchors.centerIn: parent
                            size: 26
                            appKey: energyRow.isSystem ? "" : energyRow.modelData.key
                            fallbackSymbol: energyRow.isSystem ? "memory" : energyRow.modelData.headless ? "terminal" : "apps"
                            colFallback: ClockStyle.colOnSurfaceVariant
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapTiny + 2

                        StyledText {
                            Layout.fillWidth: true
                            text: AppStats.displayName(energyRow.modelData.key)
                            font.pixelSize: ClockStyle.textNormal
                            font.weight: Font.DemiBold
                            color: ClockStyle.colOnSurface
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 6
                            radius: 3
                            color: ClockStyle.colSurfaceHigh

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: Math.max(parent.height,
                                    parent.width * (root.energyMax > 0 ? energyRow.modelData.mj / root.energyMax : 0))
                                radius: parent.radius
                                color: energyRow.isSystem ? ClockStyle.colSubtext : ClockStyle.colPrimary

                                Behavior on width {
                                    enabled: !ClockStyle.reducedMotion
                                    animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                                }
                            }
                        }
                    }

                    StyledText {
                        Layout.minimumWidth: 84
                        horizontalAlignment: Text.AlignRight
                        text: Format.energyFromMj(energyRow.modelData.mj)
                        font.family: ClockStyle.fontMain
                        font.variableAxes: ClockStyle.axesDigitsBold
                        font.pixelSize: 20
                        color: ClockStyle.colOnSurface
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.energyApps.length === 0
                text: Translation.tr("No energy recorded for this period.")
                font.pixelSize: ClockStyle.textNormal
                color: ClockStyle.colSubtext
            }
        }
    }

    /// Hour by hour or day by day, newest first; a row narrows the page to its bucket.
    component BreakdownPane: Rectangle {
        implicitHeight: breakdownColumn.implicitHeight + ClockStyle.cardPadding + ClockStyle.gapSmall
        radius: ClockStyle.radiusCard
        color: ClockStyle.colPane

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
                subtitle: Translation.tr("Level at the close · energy out of the pack")
            }

            Repeater {
                model: root.needsRebuild ? 0 : root.lastLive + 1

                Rectangle {
                    id: bucketRow
                    required property int index
                    readonly property int bucketIndex: root.lastLive - bucketRow.index
                    readonly property var bucket: root.buckets[bucketRow.bucketIndex] ?? null
                    readonly property string kind: root.bucketStates[bucketRow.bucketIndex] ?? ""
                    readonly property bool focused: root.focusedBucket === bucketRow.bucketIndex

                    Layout.fillWidth: true
                    visible: bucketRow.bucket !== null
                    implicitHeight: 56
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
                            text: bucketRow.kind === "charge" ? "battery_charging_full"
                                : bucketRow.kind === "ac" ? "power" : "battery_horiz_050"
                            iconSize: 18
                            padding: 8
                            shape: bucketRow.kind === "charge" ? MaterialShape.Shape.Sunny : MaterialShape.Shape.Cookie6Sided
                            color: bucketRow.kind === "charge" ? ClockStyle.colTertiaryContainer
                                : bucketRow.focused ? ClockStyle.colSecondaryContainerHover : ClockStyle.colSurfaceHigh
                            colSymbol: bucketRow.kind === "charge" ? ClockStyle.colOnTertiaryContainer
                                : bucketRow.focused ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurfaceVariant
                            fill: 1
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: ClockStyle.gapTiny + 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: ClockStyle.gapSmall

                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.bucketNames[bucketRow.bucketIndex] ?? ""
                                    font.pixelSize: ClockStyle.textNormal
                                    font.weight: Font.DemiBold
                                    color: bucketRow.focused ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    text: bucketRow.bucket ? `${Math.round(bucketRow.bucket.end)} %` : "—"
                                    font.pixelSize: ClockStyle.textSmall
                                    color: bucketRow.focused ? ClockStyle.colOnSecondaryContainer : ClockStyle.colSubtext
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 6
                                radius: 3
                                color: bucketRow.focused
                                    ? ColorUtils.applyAlpha(ClockStyle.colOnSecondaryContainer, 0.16) : ClockStyle.colSurfaceHigh

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: bucketRow.bucket && bucketRow.bucket.outMwh > 0 && root.maxOut > 0
                                        ? Math.max(parent.height, parent.width * Math.min(1, bucketRow.bucket.outMwh / root.maxOut))
                                        : 0
                                    radius: parent.radius
                                    color: bucketRow.kind === "charge" ? ClockStyle.colTertiary
                                        : bucketRow.focused ? ClockStyle.colOnSecondaryContainer : ClockStyle.colPrimary

                                    Behavior on width {
                                        enabled: !ClockStyle.reducedMotion
                                        animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                                    }
                                }
                            }
                        }

                        StyledText {
                            Layout.minimumWidth: 64
                            horizontalAlignment: Text.AlignRight
                            text: bucketRow.bucket && bucketRow.bucket.outMwh > 0
                                ? Format.energy(bucketRow.bucket.outMwh / 1000) : "—"
                            font.family: ClockStyle.fontMain
                            font.variableAxes: ClockStyle.axesDigitsBold
                            font.pixelSize: 20
                            color: bucketRow.focused ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface
                        }
                    }
                }
            }

            // Nothing recorded for a period still in progress is not an idle machine,
            // it is a sampler that does not know how to look.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: ClockStyle.gap
                visible: root.needsRebuild
                spacing: ClockStyle.gap

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gap

                    MaterialShapeWrappedMaterialSymbol {
                        text: "build"
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
                            text: Translation.tr("No battery history yet")
                            font.pixelSize: ClockStyle.textNormal + 1
                            font.weight: Font.Bold
                            color: ClockStyle.colOnSurface
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("The sampler records the pack alongside the apps, but only if it was built with that in it. Rebuild it, then reopen this page.")
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

    // ── No battery ──────────────────────────────────────────────────────
    ClockEmptyState {
        anchors.centerIn: parent
        width: Math.min(parent.width - ClockStyle.gapHuge * 2, 360)
        visible: !Battery.available
        symbol: "battery_unknown"
        title: Translation.tr("No battery")
        subtitle: Translation.tr("This machine runs on mains power, so there is no charge to follow.")
    }

    // Wide: the pack on the left at full height, the period's figures beside it.
    Loader {
        anchors.fill: parent
        active: Battery.available && root.wide
        visible: active
        sourceComponent: RowLayout {
            spacing: ClockStyle.paneGap

            Hero {
                Layout.preferredWidth: root.heroWidth
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

                    PeriodTiles {
                        Layout.fillWidth: true
                    }

                    EnergyPane {
                        Layout.fillWidth: true
                    }

                    BreakdownPane {
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }

    // Narrow: one scrolling column, the pack first.
    Loader {
        anchors.fill: parent
        active: Battery.available && !root.wide
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

                PeriodTiles {
                    Layout.fillWidth: true
                }

                EnergyPane {
                    Layout.fillWidth: true
                }

                BreakdownPane {
                    Layout.fillWidth: true
                }
            }
        }
    }
}
