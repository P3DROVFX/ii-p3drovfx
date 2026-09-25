import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import "UsageFormat.js" as Format

/**
 * The battery half of the usage overlay: where the charge stood, and what it cost
 * to get there.
 *
 * Built on the same day files as the app view — the sampler records the pack
 * beside the apps — so the period controls, the card grammar and the breakdown
 * list are the ones next door. Both draw the same bars the app view does; what
 * differs is what they measure, a day being the level at the close of each hour
 * and a week or a month the charge spent per day, because a level cannot be
 * summed but watt-hours can.
 */
Item {
    id: root

    /// The view to open on, named rather than numbered — see Usage.qml.
    property string initialGranularity: "day"

    property int granularityIndex: 0
    property int periodOffset: 0
    /// The hour or day the figures are narrowed to, or -1 for the whole period.
    property int focusedBucket: -1

    readonly property string granularity: periodBar.granularity
    readonly property bool isSingleDay: root.granularity === "day"
    readonly property var dates: AppStats.periodDates(root.granularity, root.periodOffset)

    /// Which bucket is now, or -1 in a period that is already over.
    readonly property int nowIndex: {
        if (root.dates.length === 0)
            return -1;
        if (root.isSingleDay)
            return root.periodOffset === 0 ? DateTime.clock.date.getHours() : -1;
        return root.dates[root.dates.length - 1] === AppStats.todayDate ? root.dates.length - 1 : -1;
    }

    readonly property int dayStride: Math.max(1, Math.ceil(root.dates.length / 10))

    /// The dates the figures cover: the whole period, or the one day picked out of
    /// a week or a month.
    readonly property var targetDates: {
        if (root.focusedBucket >= 0 && !root.isSingleDay) {
            const date = root.dates[root.focusedBucket];
            return date ? [date] : root.dates;
        }
        return root.dates;
    }

    /// Touching `history` is what makes every figure recompute when a day file
    /// lands; `dates` alone does not change when the data does.
    readonly property var rollup: {
        AppStats.history;
        const opts = {};
        if (root.focusedBucket >= 0 && root.isSingleDay) {
            opts.hourFrom = root.focusedBucket;
            opts.hourTo = root.focusedBucket;
        }
        return AppStats.batteryRollup(root.targetDates, opts);
    }

    /// Per-bucket rollups: one per hour of a day, or one per day of a week or month.
    readonly property var buckets: {
        AppStats.history;
        if (root.isSingleDay) {
            const date = root.dates[0];
            if (!date)
                return [];
            return AppStats.batteryHours(date);
        }
        // A day's rollup carries the same figures under other names — where it left
        // the pack is `last` rather than `end` — so it is renamed into the shape of
        // an hour and everything downstream reads one bucket. A day that recorded
        // nothing becomes null for the same reason an unrecorded hour is one.
        return AppStats.batteryDaily(root.dates).map(day => day.hours === 0 ? null : ({
                    "end": day.last,
                    "low": day.low,
                    "high": day.high,
                    "outMwh": day.outMwh,
                    "inMwh": day.inMwh,
                    "offAc": day.offAc,
                    "charging": day.charging,
                    "onAc": day.onAc
                }));
    }

    /// Level at the close of each hour, 0 where the hour holds nothing — an hour
    /// the machine was off draws as an empty slot, the same as an hour that used
    /// no energy does in the app view. Only the day view has one: a week's worth
    /// of levels is a sawtooth of overnight charges that says nothing a daily
    /// total does not say better.
    readonly property var levels: root.isSingleDay ? root.buckets.map(bucket => bucket ? bucket.end : 0) : []

    /// What the pack was doing in each hour, by whichever of the three it spent
    /// most of the hour in.
    readonly property var levelStates: root.buckets.map(bucket => {
        if (!bucket)
            return "";
        if (bucket.charging >= bucket.offAc && bucket.charging >= bucket.onAc)
            return "charge";
        return bucket.offAc >= bucket.onAc ? "off" : "ac";
    })

    /// Milliwatt-hours out of the pack per bucket, for the week and month bars.
    readonly property var dischargeValues: root.buckets.map(bucket => bucket ? bucket.outMwh : 0)

    readonly property var chartLabels: {
        if (root.isSingleDay)
            return Array.from({
                "length": 24
            }, (unused, hour) => Format.hourLabel(hour));

        const first = (root.dates.length - 1) % root.dayStride;
        return root.dates.map((date, index) => Format.dayLabel(date, index === first || index === root.dates.length - 1 || date.slice(-2) === "01"));
    }

    /// Buckets past the current hour or day are not empty, they have not happened.
    function trim(list) {
        if (root.periodOffset === 0 && root.nowIndex >= 0 && root.nowIndex < list.length)
            return list.slice(0, root.nowIndex + 1);
        return list;
    }

    readonly property var activeLabels: root.trim(root.chartLabels)
    readonly property var activeBuckets: root.trim(root.buckets)
    readonly property real fullMwh: root.rollup.fullMwh

    /// Discharge as a share of a full pack, which is the figure that survives being
    /// compared between machines — 12 Wh means nothing without the capacity.
    readonly property real dischargedPercent: root.fullMwh > 0 ? root.rollup.outMwh / root.fullMwh * 100 : NaN

    /// Mean draw while actually running off the pack, in watts. Time plugged in is
    /// excluded, or a day spent mostly on AC would report a machine that sips.
    readonly property real averageWatts: root.rollup.offAc > 0 ? root.rollup.outMwh / 1000 / (root.rollup.offAc / 3600) : NaN

    /// How long a full charge lasts at that draw. An estimate from this period's
    /// own behaviour rather than the firmware's, so it answers "at this rate".
    readonly property real runtimeHours: (!isNaN(root.averageWatts) && root.averageWatts > 0 && root.fullMwh > 0) ? root.fullMwh / 1000 / root.averageWatts : NaN

    /// Nothing recorded for a period that is still running means the sampler is not
    /// writing it — almost always a binary built before it knew about batteries.
    readonly property bool needsRebuild: root.rollup.hours === 0 && root.periodOffset === 0

    function stepPeriod(delta) {
        const next = Math.min(0, root.periodOffset + delta);
        if (next === root.periodOffset)
            return;
        if (next < root.periodOffset && !periodBar.canGoBack)
            return;
        root.periodOffset = next;
        root.focusedBucket = -1;
    }

    function setGranularity(index) {
        if (root.granularityIndex === index)
            return;
        root.granularityIndex = index;
        root.periodOffset = 0;
        root.focusedBucket = -1;
    }

    function focusBucket(index) {
        root.focusedBucket = root.focusedBucket === index ? -1 : index;
    }

    function refresh() {
        AppStats.ensureDates(root.dates);
        AppStats.refresh();
    }

    /// Handles a key press forwarded by the window. Returns whether it was ours.
    function handleKey(key) {
        switch (key) {
        case Qt.Key_Left:
            root.stepPeriod(-1);
            return true;
        case Qt.Key_Right:
            root.stepPeriod(1);
            return true;
        case Qt.Key_PageUp:
            root.setGranularity(Math.min(periodBar.granularities.length - 1, root.granularityIndex + 1));
            return true;
        case Qt.Key_PageDown:
            root.setGranularity(Math.max(0, root.granularityIndex - 1));
            return true;
        case Qt.Key_Home:
            root.periodOffset = 0;
            return true;
        case Qt.Key_Escape:
            if (root.focusedBucket < 0)
                return false;
            root.focusedBucket = -1;
            return true;
        }
        return false;
    }

    onDatesChanged: AppStats.ensureDates(root.dates)

    Component.onCompleted: {
        for (let i = 0; i < periodBar.granularities.length; i++) {
            if (periodBar.granularities[i].key === root.initialGranularity)
                root.granularityIndex = i;
        }
        // The window asks the sampler for a fresh flush once its entrance ends.
        AppStats.ensureDates(root.dates);
    }

    component Card: Rectangle {
        color: Appearance.colors.colLayer1
        radius: Appearance.rounding.normal
    }

    component StatChip: ColumnLayout {
        id: chip

        required property string label
        required property string value
        property string icon: ""
        property string caption: ""
        property bool shown: true

        visible: chip.shown
        spacing: 2

        RowLayout {
            spacing: 4

            MaterialSymbol {
                visible: chip.icon.length > 0
                text: chip.icon
                iconSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }

            StyledText {
                text: chip.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        StyledText {
            text: chip.value
            font.pixelSize: Appearance.font.pixelSize.large
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer1
        }

        StyledText {
            visible: chip.caption.length > 0
            text: chip.caption
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }

    /// One hour or one day of the breakdown: where the level ended, and what left
    /// the pack over it. The bar is drawn against the heaviest bucket in the list,
    /// for the same reason the app rows are.
    component BreakdownRow: Rectangle {
        id: row

        required property string label
        required property var bucket
        required property real maxOut
        required property bool focused

        signal clicked

        implicitHeight: 50
        radius: Appearance.rounding.small
        color: {
            if (row.focused)
                return Appearance.colors.colSecondaryContainer;
            return rowArea.containsMouse ? Appearance.colors.colLayer2Hover : "transparent";
        }

        MouseArea {
            id: rowArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.clicked()
        }

        RowLayout {
            spacing: 10

            anchors {
                fill: parent
                leftMargin: 12
                rightMargin: 12
            }

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: {
                    if (!row.bucket)
                        return "battery_unknown";
                    if (row.bucket.charging > 0)
                        return "battery_charging_full";
                    return row.bucket.offAc > 0 ? "battery_horiz_050" : "power";
                }
                iconSize: 20
                color: row.focused ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    StyledText {
                        Layout.fillWidth: true
                        text: row.label
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: row.focused ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                    }

                    StyledText {
                        text: row.bucket ? `${Math.round(row.bucket.end)} %` : "—"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }

                    StyledText {
                        text: row.bucket && row.bucket.outMwh > 0 ? Format.energy(row.bucket.outMwh / 1000) : "—"
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: row.focused ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 4
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colLayer2

                    Rectangle {
                        width: parent.width * (row.maxOut > 0 && row.bucket ? Math.min(1, row.bucket.outMwh / row.maxOut) : 0)
                        radius: parent.radius
                        color: row.bucket && row.bucket.charging > 0 ? Appearance.colors.colTertiary : Appearance.colors.colPrimary

                        anchors {
                            left: parent.left
                            top: parent.top
                            bottom: parent.bottom
                        }

                        Behavior on width {
                            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                        }
                    }
                }
            }
        }

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            UsagePeriodBar {
                id: periodBar

                granularityIndex: root.granularityIndex
                periodOffset: root.periodOffset
                onGranularityPicked: index => root.setGranularity(index)
                onStepped: delta => root.stepPeriod(delta)
                onPeriodReset: root.periodOffset = 0
            }

            Item {
                Layout.fillWidth: true
            }

            // The pack itself, which is the same whichever period is on screen.
            RowLayout {
                spacing: 6

                MaterialSymbol {
                    text: Battery.isCharging ? "battery_charging_full" : "battery_horiz_075"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer0
                }

                StyledText {
                    text: `${Math.round(Battery.percentage * 100)} %`
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer0
                }

                StyledText {
                    text: {
                        if (Battery.isCharging)
                            return Translation.tr("charging");
                        if (Battery.chargeLimitReached)
                            return Translation.tr("held at %1 %").arg(Battery.chargeLimit);
                        return Battery.isPluggedIn ? Translation.tr("plugged in") : Translation.tr("on battery");
                    }
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12

                Card {
                    Layout.fillWidth: true
                    implicitHeight: summaryFlow.implicitHeight + 32

                    Flow {
                        id: summaryFlow

                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: 16
                        }
                        spacing: 22

                        StatChip {
                            icon: "battery_alert"
                            label: Translation.tr("Discharged")
                            value: root.rollup.outMwh > 0 ? Format.energy(root.rollup.outMwh / 1000) : "—"
                            caption: isNaN(root.dischargedPercent) || root.dischargedPercent <= 0 ? "" : Translation.tr("%1 % of a full charge").arg(root.dischargedPercent.toFixed(root.dischargedPercent < 10 ? 1 : 0))
                        }

                        StatChip {
                            icon: "bolt"
                            label: Translation.tr("Average draw")
                            value: isNaN(root.averageWatts) ? "—" : `${root.averageWatts.toFixed(1)} W`
                            caption: isNaN(root.runtimeHours) ? "" : Translation.tr("about %1 from full").arg(Format.duration(root.runtimeHours * 3600))
                        }

                        StatChip {
                            icon: "battery_horiz_050"
                            label: Translation.tr("On battery")
                            value: Format.duration(root.rollup.offAc)
                        }

                        StatChip {
                            icon: "battery_charging_full"
                            label: Translation.tr("Charging")
                            value: Format.duration(root.rollup.charging)
                            caption: root.rollup.inMwh > 0 ? Translation.tr("%1 in").arg(Format.energy(root.rollup.inMwh / 1000)) : ""
                        }

                        StatChip {
                            icon: "power"
                            label: Translation.tr("Plugged in, idle")
                            value: Format.duration(root.rollup.onAc)
                        }

                        StatChip {
                            shown: !isNaN(root.rollup.low)
                            icon: "trending_down"
                            label: Translation.tr("Lowest level")
                            value: `${Math.round(root.rollup.low)} %`
                            caption: isNaN(root.rollup.high) ? "" : Translation.tr("peaked at %1 %").arg(Math.round(root.rollup.high))
                        }

                        // Facts about the pack rather than about the period, kept
                        // here because this is the one screen that is about it.
                        StatChip {
                            shown: Battery.health > 0
                            icon: "health_metrics"
                            label: Translation.tr("Health")
                            value: `${Math.round(Battery.health)} %`
                            caption: Battery.cycles >= 0 ? Translation.tr("%1 cycles").arg(Battery.cycles) : ""
                        }

                        StatChip {
                            shown: root.fullMwh > 0
                            icon: "battery_profile"
                            label: Translation.tr("Capacity")
                            value: Format.energy(root.fullMwh / 1000)
                            caption: Battery.chargeLimitActive ? Translation.tr("charging stops at %1 %").arg(Battery.chargeLimit) : ""
                        }
                    }
                }

                Card {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ColumnLayout {
                        anchors {
                            fill: parent
                            margins: 16
                        }
                        spacing: 12

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: root.isSingleDay ? Translation.tr("Charge level") : Translation.tr("Discharged per day")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                            }

                            RippleButton {
                                visible: root.focusedBucket >= 0
                                implicitHeight: 30
                                buttonRadius: Appearance.rounding.full
                                horizontalPadding: 12
                                onClicked: root.focusedBucket = -1

                                contentItem: StyledText {
                                    text: {
                                        if (root.focusedBucket < 0)
                                            return "";
                                        const label = root.activeLabels[root.focusedBucket] ?? "";
                                        return Translation.tr("Clear time filter (%1)").arg(label);
                                    }
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnLayer1
                                }
                            }
                        }

                        UsageBarChart {
                            visible: root.isSingleDay
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            values: root.trim(root.levels)
                            labels: root.activeLabels
                            highlightIndex: root.periodOffset === 0 ? root.nowIndex : -1
                            focusedIndex: root.focusedBucket
                            labelStride: root.activeLabels.length <= 6 ? 1 : Math.ceil(root.activeLabels.length / 6)
                            // A level is a share of a whole pack, so the axis is the
                            // pack rather than the fullest hour on screen — half the
                            // height has to mean half a battery all day.
                            axisCeiling: 100
                            formatValue: value => `${Math.round(value)} %`
                            formatTick: value => `${Math.round(value)} %`
                            // A night on the charger should not look like an evening
                            // spent draining the pack, however similar the levels.
                            colorAt: index => {
                                const state = root.trim(root.levelStates)[index] ?? "";
                                if (state === "charge")
                                    return Appearance.colors.colTertiary;
                                if (state === "ac")
                                    return Appearance.colors.colSecondaryContainer;
                                return Appearance.colors.colPrimary;
                            }
                            onBarClicked: index => root.focusBucket(index)
                        }

                        UsageBarChart {
                            visible: !root.isSingleDay
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            values: root.trim(root.dischargeValues)
                            labels: root.activeLabels
                            tooltipLabels: root.trim(root.dates)
                            labelStride: root.dayStride
                            labelAnchorEnd: true
                            highlightIndex: root.periodOffset === 0 ? root.nowIndex : -1
                            focusedIndex: root.focusedBucket
                            // Milliwatt-hours per watt-hour, the figure the axis is
                            // labelled in.
                            valueUnit: 1000
                            formatValue: value => Format.energy(value / 1000)
                            formatTick: value => Format.energy(value / 1000)
                            onBarClicked: index => root.focusBucket(index)
                        }
                    }
                }
            }

            Card {
                Layout.fillHeight: true
                implicitWidth: 400

                ColumnLayout {
                    anchors {
                        fill: parent
                        topMargin: 16
                        bottomMargin: 8
                        leftMargin: 8
                        rightMargin: 8
                    }
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        Layout.rightMargin: 4
                        spacing: 8

                        StyledText {
                            Layout.fillWidth: true
                            text: root.isSingleDay ? Translation.tr("Hour by hour") : Translation.tr("Day by day")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnLayer1
                        }

                        RippleButton {
                            implicitWidth: 32
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            onClicked: root.refresh()

                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "refresh"
                                iconSize: 18
                                color: Appearance.colors.colSubtext
                            }

                            StyledToolTip {
                                text: Translation.tr("Refresh")
                            }
                        }
                    }

                    StyledListView {
                        id: breakdownList

                        readonly property real maxOut: {
                            let max = 0;
                            for (const bucket of root.buckets) {
                                if (bucket)
                                    max = Math.max(max, bucket.outMwh);
                            }
                            return max;
                        }

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 2
                        visible: !root.needsRebuild
                        // Newest first: the interesting end of today is the end of it.
                        model: root.activeBuckets.length

                        delegate: BreakdownRow {
                            required property int index

                            readonly property int bucketIndex: root.activeBuckets.length - 1 - index

                            width: breakdownList.width
                            visible: root.buckets[bucketIndex] !== null && root.buckets[bucketIndex] !== undefined
                            height: visible ? implicitHeight : 0
                            label: root.chartLabels[bucketIndex] ?? ""
                            bucket: root.buckets[bucketIndex]
                            maxOut: breakdownList.maxOut
                            focused: root.focusedBucket === bucketIndex
                            onClicked: root.focusBucket(bucketIndex)
                        }
                    }

                    // Nothing recorded for a period still in progress is not an idle
                    // machine, it is a sampler that does not know how to look.
                    HelperCodeBox {
                        Layout.fillWidth: true
                        Layout.margins: 8
                        visible: root.needsRebuild
                        icon: "terminal"
                        title: Translation.tr("No battery history yet")
                        text: Translation.tr("The sampler records the pack alongside the apps, but only if it was built with that in it. Rebuild it, then reopen this panel.")
                        codeSnippet: `${Directories.rustHelpersScriptPath.replace(FileUtils.trimFileProtocol(Directories.home), "~")} build app_stats`
                        snippetWrapMode: Text.Wrap
                    }

                    Item {
                        Layout.fillHeight: true
                        visible: root.needsRebuild
                    }
                }
            }
        }
    }
}
