pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

/**
 * Everything the stored results add up to, laid out the way Monkeytype's
 * account page reads: lifetime totals, personal bests per test length, an
 * activity map of the last year, and the shape of the scores over time.
 *
 * It only reads TypingHistory. Nothing here can start, stop or alter a test,
 * so it is safe to open mid-session — the surface pauses the run for it the
 * same way it does for settings and history.
 */
Item {
    id: root

    /** Chart and histogram window, in days. 0 means everything stored. */
    property int rangeDays: 0

    readonly property var ranged: TypingHistory.resultsSince(
        root.rangeDays > 0 ? Date.now() - root.rangeDays * 86400000 : 0)
    readonly property bool hasResults: TypingHistory.results.length > 0

    readonly property var timePresets: [15, 30, 60, 120]
    readonly property var wordPresets: [10, 25, 50, 100]

    function formatDuration(seconds) {
        const total = Math.max(0, Math.round(seconds));
        const hours = Math.floor(total / 3600);
        const minutes = Math.floor((total % 3600) / 60);
        const rest = total % 60;
        const pad = value => (value < 10 ? "0" : "") + String(value);
        return pad(hours) + ":" + pad(minutes) + ":" + pad(rest);
    }

    // ── Small parts ───────────────────────────────────────────────────────
    component SectionTitle: StyledText {
        Layout.topMargin: Appearance.sizes.elevationMargin / 2
        font.pixelSize: Appearance.font.pixelSize.small
        font.weight: Font.DemiBold
        color: Appearance.colors.colPrimary
    }

    component Card: Rectangle {
        // The holder is a layout, not a plain Item: an Item takes no implicit
        // height from its children, so a card built on one collapses to its
        // padding and its content spills over the next section.
        default property alias cardContent: cardColumn.data
        Layout.fillWidth: true
        implicitHeight: cardColumn.implicitHeight + 24
        radius: Appearance.rounding.small
        color: Appearance.colors.colSurfaceContainerLow

        ColumnLayout {
            id: cardColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 6
        }
    }

    component Headline: ColumnLayout {
        id: headline
        property string label: ""
        property string value: ""
        property string caption: ""
        spacing: -2

        StyledText {
            text: headline.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
        StyledText {
            text: headline.value
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.hugeass * 1.35
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnSurface
        }
        StyledText {
            visible: headline.caption.length > 0
            text: headline.caption
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
    }

    component RangeChip: RippleButton {
        id: rangeChip
        property string label: ""
        property int days: 0
        readonly property bool active: root.rangeDays === rangeChip.days

        implicitWidth: rangeChipLabel.implicitWidth + 24
        implicitHeight: 30
        buttonRadius: Appearance.rounding.full
        colBackground: rangeChip.active ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh
        colBackgroundHover: rangeChip.active ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
        colRipple: rangeChip.active ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive
        onClicked: root.rangeDays = rangeChip.days

        StyledText {
            id: rangeChipLabel
            anchors.centerIn: parent
            text: rangeChip.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: rangeChip.active ? Font.DemiBold : Font.Normal
            color: rangeChip.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurfaceVariant
        }
    }

    // ── Empty state ───────────────────────────────────────────────────────
    ColumnLayout {
        anchors.centerIn: parent
        visible: !root.hasResults
        spacing: 4

        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            text: "monitoring"
            iconSize: Appearance.font.pixelSize.hugeass * 2
            color: Appearance.colors.colSubtext
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Config.options.search.typingTest.history.enable
                ? Translation.tr("Finish a few tests and this fills in")
                : Translation.tr("Score history is switched off in the settings page")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
    }

    StyledFlickable {
        id: scroller
        anchors.fill: parent
        visible: root.hasResults
        contentHeight: statsColumn.implicitHeight
        clip: true

        ColumnLayout {
            id: statsColumn
            width: scroller.width
            spacing: 6

            // ── Lifetime totals ───────────────────────────────────────
            Card {
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Appearance.sizes.elevationMargin * 2

                    Headline {
                        label: Translation.tr("tests started")
                        value: String(TypingHistory.startedTotal)
                    }
                    Headline {
                        label: Translation.tr("tests completed")
                        value: String(TypingHistory.completedTotal)
                        caption: TypingHistory.startedTotal > 0
                            ? Math.round(TypingHistory.completedTotal / TypingHistory.startedTotal * 100) + "%"
                            : ""
                    }
                    Headline {
                        label: Translation.tr("time typing")
                        value: root.formatDuration(TypingHistory.typingSeconds)
                    }
                    Headline {
                        label: Translation.tr("average wpm")
                        value: String(Math.round(TypingHistory.averageWpm))
                        caption: Math.round(TypingHistory.averageAccuracy) + "%"
                    }

                    Item { Layout.fillWidth: true }
                }
            }

            // ── Personal bests ────────────────────────────────────────
            SectionTitle {
                text: Translation.tr("Personal bests")
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: [
                        { mode: "time", presets: root.timePresets, suffix: Translation.tr("seconds") },
                        { mode: "words", presets: root.wordPresets, suffix: Translation.tr("words") }
                    ]

                    delegate: Rectangle {
                        id: bestGroup
                        required property var modelData

                        Layout.fillWidth: true
                        implicitHeight: bestRow.implicitHeight + 24
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colSurfaceContainerLow

                        RowLayout {
                            id: bestRow
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 0

                            Repeater {
                                model: bestGroup.modelData.presets

                                delegate: ColumnLayout {
                                    id: bestCell
                                    required property int modelData
                                    readonly property var best: TypingHistory.bestOf(bestGroup.modelData.mode, bestCell.modelData)

                                    Layout.fillWidth: true
                                    spacing: -2

                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: String(bestCell.modelData) + " " + bestGroup.modelData.suffix
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colSubtext
                                    }
                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: bestCell.best ? String(Math.round(bestCell.best.wpm)) : "—"
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: Appearance.font.pixelSize.hugeass * 1.2
                                        font.weight: Font.DemiBold
                                        color: bestCell.best ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                    }
                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: bestCell.best ? Math.round(bestCell.best.accuracy) + "%" : ""
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnSurfaceVariant
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Activity map ──────────────────────────────────────────
            SectionTitle {
                text: Translation.tr("Activity")
            }

            Card {
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    // One hovered day at a time, read here instead of through
                    // 371 tooltips — see the note on the map below.
                    StyledText {
                        Layout.fillWidth: true
                        text: activityMap.hoveredIndex >= 0
                            ? Translation.tr("%1 · %2 tests")
                                .arg(Qt.formatDate(activityMap.dateAt(activityMap.hoveredIndex), "dd MMM yyyy"))
                                .arg(String(activityMap.countAt(activityMap.hoveredIndex)))
                            : (activityMap.total > 0
                                ? Translation.tr("%1 tests in the last year").arg(String(activityMap.total))
                                : Translation.tr("Daily activity is tracked from now on"))
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: activityMap.hoveredIndex >= 0
                            ? Appearance.colors.colOnSurface : Appearance.colors.colOnSurfaceVariant
                    }

                    StyledText {
                        text: Translation.tr("less")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    Repeater {
                        model: 5
                        delegate: Rectangle {
                            required property int index
                            implicitWidth: activityMap.cell
                            implicitHeight: activityMap.cell
                            radius: Appearance.rounding.unsharpen
                            color: activityMap.shade(index)
                        }
                    }
                    StyledText {
                        text: Translation.tr("more")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }

                // One column per week, one row per weekday — the same reading
                // order as the contribution map it borrows from.
                Item {
                    id: activityMap
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    implicitHeight: 7 * activityMap.cell + 6 * activityMap.gap

                    readonly property int weeks: 53
                    readonly property real gap: 3
                    readonly property real cell: Math.max(6,
                        Math.floor((width - (activityMap.weeks - 1) * activityMap.gap) / activityMap.weeks))
                    /** Midnight on the Sunday that opens the first column. */
                    readonly property var origin: {
                        const today = new Date();
                        today.setHours(0, 0, 0, 0);
                        const start = new Date(today.getTime() - (activityMap.weeks - 1) * 7 * 86400000);
                        start.setDate(start.getDate() - start.getDay());
                        return start;
                    }
                    readonly property int total: {
                        let total = 0;
                        for (const entry of Array.from(TypingHistory.activity))
                            total += entry.n ?? 0;
                        return total;
                    }
                    readonly property int peak: {
                        let peak = 1;
                        for (const entry of Array.from(TypingHistory.activity))
                            peak = Math.max(peak, entry.n ?? 0);
                        return peak;
                    }

                    /**
                     * The hovered cell, resolved from one handler on the whole
                     * map. A StyledToolTip per day would be 371 popups, and
                     * StyledToolTip reads `parent.hovered` — a plain Rectangle
                     * has no such property, so every one of them would read
                     * `undefined` and show itself the moment the page opened.
                     */
                    property int hoveredIndex: -1

                    function dateAt(index) {
                        return new Date(activityMap.origin.getTime() + index * 86400000);
                    }

                    function countAt(index) {
                        return TypingHistory.testsOn(Qt.formatDate(activityMap.dateAt(index), "yyyy-MM-dd"));
                    }

                    function shade(level) {
                        if (level <= 0)
                            return ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.92);
                        return ColorUtils.transparentize(Appearance.colors.colPrimary, 0.85 - level * 0.2);
                    }

                    function levelAt(count) {
                        if (count <= 0)
                            return 0;
                        return Math.max(1, Math.min(4, Math.ceil(count / activityMap.peak * 4)));
                    }

                    HoverHandler {
                        id: mapHover
                        onPointChanged: {
                            const step = activityMap.cell + activityMap.gap;
                            const column = Math.floor(point.position.x / step);
                            const row = Math.floor(point.position.y / step);
                            if (column < 0 || column >= activityMap.weeks || row < 0 || row > 6) {
                                activityMap.hoveredIndex = -1;
                                return;
                            }
                            const index = column * 7 + row;
                            activityMap.hoveredIndex = activityMap.dateAt(index).getTime() <= Date.now()
                                ? index : -1;
                        }
                        onHoveredChanged: {
                            if (!mapHover.hovered)
                                activityMap.hoveredIndex = -1;
                        }
                    }

                    Repeater {
                        model: activityMap.weeks * 7

                        delegate: Rectangle {
                            id: dayCell
                            required property int index

                            x: Math.floor(dayCell.index / 7) * (activityMap.cell + activityMap.gap)
                            y: (dayCell.index % 7) * (activityMap.cell + activityMap.gap)
                            width: activityMap.cell
                            height: activityMap.cell
                            radius: Appearance.rounding.unsharpen
                            // Days that have not happened yet are simply absent.
                            visible: activityMap.dateAt(dayCell.index).getTime() <= Date.now()
                            color: activityMap.hoveredIndex === dayCell.index
                                ? Appearance.colors.colPrimary
                                : activityMap.shade(activityMap.levelAt(activityMap.countAt(dayCell.index)))
                        }
                    }
                }
            }

            // ── Range filter ──────────────────────────────────────────
            SectionTitle {
                text: Translation.tr("Scores")
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 5

                RangeChip { label: Translation.tr("last day"); days: 1 }
                RangeChip { label: Translation.tr("last week"); days: 7 }
                RangeChip { label: Translation.tr("last month"); days: 30 }
                RangeChip { label: Translation.tr("last 3 months"); days: 90 }
                RangeChip { label: Translation.tr("all time"); days: 0 }

                Item { Layout.fillWidth: true }

                StyledText {
                    text: Translation.tr("%1 tests").arg(String(root.ranged.length))
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }

            // ── Speed over time ───────────────────────────────────────
            Card {
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Item {
                        id: speedChart
                        Layout.fillWidth: true
                        Layout.preferredHeight: 150

                        // Oldest first, so the line reads left to right.
                        readonly property var series: Array.from(root.ranged)
                            .slice()
                            .reverse()
                            .map(entry => entry.wpm ?? 0)
                        readonly property real peak: {
                            let peak = 1;
                            for (const value of speedChart.series)
                                peak = Math.max(peak, value);
                            return peak * 1.08;
                        }
                        readonly property real floorValue: {
                            let trough = speedChart.peak;
                            for (const value of speedChart.series)
                                trough = Math.min(trough, value);
                            return Math.max(0, trough * 0.9);
                        }
                        readonly property real mean: {
                            if (speedChart.series.length === 0)
                                return 0;
                            return speedChart.series.reduce((total, value) => total + value, 0)
                                / speedChart.series.length;
                        }

                        function normalize(value) {
                            const span = Math.max(1, speedChart.peak - speedChart.floorValue);
                            return Math.max(0, Math.min(1, (value - speedChart.floorValue) / span));
                        }

                        StyledText {
                            anchors.centerIn: parent
                            visible: speedChart.series.length < 2
                            text: Translation.tr("Not enough tests in this range")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }

                        // The average, so a run reads as above or below par.
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            visible: speedChart.series.length >= 2
                            y: parent.height - speedChart.normalize(speedChart.mean) * parent.height
                            implicitHeight: 1
                            color: Appearance.colors.colOutlineVariant
                        }

                        Graph {
                            anchors.fill: parent
                            visible: speedChart.series.length >= 2
                            values: speedChart.series.map(value => speedChart.normalize(value))
                            color: Appearance.colors.colPrimary
                            fillOpacity: 0.18
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Appearance.sizes.elevationMargin * 2

                        StyledText {
                            text: Translation.tr("average %1 wpm").arg(String(Math.round(speedChart.mean)))
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                        StyledText {
                            text: Translation.tr("best %1 wpm").arg(String(Math.round(
                                root.ranged.reduce((best, entry) => Math.max(best, entry.wpm ?? 0), 0))))
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                        Item { Layout.fillWidth: true }
                    }
                }
            }

            // ── Distribution ──────────────────────────────────────────
            Card {
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    StyledText {
                        text: Translation.tr("Tests by speed")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }

                    RowLayout {
                        id: histogram
                        Layout.fillWidth: true
                        Layout.preferredHeight: 130
                        spacing: 4

                        /** Ten-wpm buckets spanning the range that has data. */
                        readonly property var buckets: {
                            const entries = Array.from(root.ranged);
                            if (entries.length === 0)
                                return [];
                            let highest = 0;
                            for (const entry of entries)
                                highest = Math.max(highest, entry.wpm ?? 0);
                            const count = Math.max(1, Math.floor(highest / 10) + 1);
                            const buckets = [];
                            for (let index = 0; index < count; index++)
                                buckets.push({ from: index * 10, tests: 0 });
                            for (const entry of entries) {
                                const index = Math.min(count - 1, Math.floor((entry.wpm ?? 0) / 10));
                                buckets[index].tests++;
                            }
                            return buckets;
                        }
                        readonly property int peak: {
                            let peak = 1;
                            for (const bucket of histogram.buckets)
                                peak = Math.max(peak, bucket.tests);
                            return peak;
                        }

                        Repeater {
                            model: histogram.buckets

                            delegate: ColumnLayout {
                                id: bar
                                required property var modelData

                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 4

                                Item { Layout.fillHeight: true }

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    visible: bar.modelData.tests > 0
                                    text: String(bar.modelData.tests)
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    // A bucket with no tests still shows a sliver,
                                    // so the axis reads as continuous.
                                    Layout.preferredHeight: Math.max(2,
                                        bar.modelData.tests / histogram.peak * 84)
                                    topLeftRadius: Appearance.rounding.unsharpenmore
                                    topRightRadius: Appearance.rounding.unsharpenmore
                                    color: bar.modelData.tests > 0
                                        ? Appearance.colors.colPrimary
                                        : ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.9)

                                    Behavior on Layout.preferredHeight {
                                        NumberAnimation {
                                            duration: Appearance.animation.elementMoveFast.duration
                                            easing.type: Appearance.animation.elementMoveFast.type
                                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                        }
                                    }
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: String(bar.modelData.from)
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    TypingStageFade {
        target: scroller
        fadeSize: 36
    }
}
