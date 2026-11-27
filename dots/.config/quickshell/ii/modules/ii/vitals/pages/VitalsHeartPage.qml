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
import qs.modules.ii.health.components
import qs.modules.ii.usage
import qs.modules.ii.usage.limits
import qs.modules.ii.vitals.components

/**
 * Heart: one chosen day as a line inside its low–high band, the fortnight around it as
 * range bars (a click picks a day), then a tile per other heart type with its newest
 * reading and a month's trend. An hour of the day opens a sheet with its readings.
 */
VitalsPage {
    id: root

    readonly property string today: VitalsFormat.dateOf(root.now)
    readonly property var present: VitalsService.present
    readonly property bool hasHeartRate: root.present.heartRate === true
    readonly property string oldest: VitalsService.dates.length > 0 ? VitalsService.dates[0] : root.today

    // ── The chosen day ──────────────────────────────────────────────────
    property string chosenDate: ""
    readonly property int dayOffset: root.chosenDate !== "" ? -VitalsFormat.daysBetween(root.chosenDate, root.today) : 0
    readonly property var dayRange: {
        VitalsService.dataVersion;
        return VitalsService.summary(root.chosenDate)?.s?.heartRate ?? null;
    }
    readonly property var latestHeart: {
        VitalsService.dataVersion;
        return root.hasHeartRate ? VitalsService.latest("heartRate") : null;
    }
    /// The chosen day's readings ([[minute, bpm]]) and the slots the chart draws.
    property var bins: []
    property int binMin: 1
    property var slots: []

    // ── The fortnight (ends today, or on the chosen day when that is older) ──
    readonly property string fortnightEnd: root.chosenDate !== "" && VitalsFormat.daysBetween(root.chosenDate, root.today) > 13 ? root.chosenDate : root.today
    readonly property var fortnight: Array.from({ length: 14 }, (_, i) => VitalsFormat.addDays(root.fortnightEnd, i - 13))
    readonly property var fortnightRanges: {
        VitalsService.dataVersion;
        return root.fortnight.map(d => {
            const r = VitalsService.summary(d)?.s?.heartRate;
            return r ? { min: r[0], avg: r[1], max: r[2] } : null;
        });
    }

    readonly property var tileKeys: VitalsTypes.keysFor("heart", root.present).filter(k => k !== "heartRate")

    function stepDay(delta: int): void {
        const next = VitalsFormat.addDays(root.chosenDate, delta);
        if (next > root.today || next < root.oldest)
            return;
        root.chosenDate = next;
    }

    function refresh(): void {
        const hr = root.chosenDate !== "" ? VitalsService.day(root.chosenDate)?.samples?.heartRate : null;
        root.bins = hr?.bins ?? [];
        root.binMin = hr?.binMin ?? 1;
        root.slots = root.aggregate(root.bins, root.binMin <= 1 ? 5 : 15);
    }

    /// Readings folded into equal slots of `slotMin` minutes: {min, avg, max} or null.
    function aggregate(bins: var, slotMin: int): var {
        const n = Math.ceil(1440 / slotMin);
        const acc = new Array(n).fill(null);
        for (const b of bins) {
            const i = Math.floor(b[0] / slotMin);
            if (i < 0 || i >= n)
                continue;
            const a = acc[i] ?? (acc[i] = { min: Infinity, max: -Infinity, sum: 0, n: 0 });
            a.min = Math.min(a.min, b[1]);
            a.max = Math.max(a.max, b[1]);
            a.sum += b[1];
            a.n++;
        }
        return acc.map(a => a ? { min: a.min, avg: a.sum / a.n, max: a.max } : null);
    }

    function openHour(hour: int): void {
        if (hour >= 0)
            root.panels.show(hourSheet, { date: root.chosenDate, hour: hour });
    }

    function digits(v: real): string {
        return Number(v).toLocaleString(Qt.locale(), "f", 0);
    }

    Component.onCompleted: {
        root.chosenDate = root.latestHeart?.date ?? root.today;
        root.refresh();
    }
    onChosenDateChanged: Qt.callLater(root.refresh)

    Connections {
        target: VitalsService
        function onDataVersionChanged() {
            root.refresh();
        }
        function onDayLoaded(date) {
            if (date === root.chosenDate)
                root.refresh();
        }
    }

    pageSubtitle: [
        root.hasHeartRate ? AppStats.periodLabel("day", root.dayOffset) : "",
        root.latestHeart?.time ? Translation.tr("heart rate as of %1").arg(VitalsFormat.asOf(root.latestHeart.time, root.latestHeart.date, root.now)) : ""
    ].filter(s => s.length > 0).join(" · ")

    function handleKey(key: int, modifiers: int): bool {
        if (!root.hasHeartRate || (modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)))
            return false;
        if (key === Qt.Key_Home) {
            root.chosenDate = root.today;
            return true;
        }
        if (key === Qt.Key_Left || key === Qt.Key_Right) {
            root.stepDay(key === Qt.Key_Left ? -1 : 1);
            return true;
        }
        if (key === Qt.Key_Return || key === Qt.Key_Enter) {
            // The newest hour that has readings.
            for (let i = root.slots.length - 1; i >= 0; i--) {
                if (root.slots[i]) {
                    root.openHour(Math.floor(i * 24 / root.slots.length));
                    break;
                }
            }
            return true;
        }
        return false;
    }

    // ── Layout ──────────────────────────────────────────────────────────
    readonly property real gap: ClockStyle.gap
    readonly property real contentWidth: root.width - ClockStyle.gapTiny * 2
    readonly property real contentLayoutWidth: root.layoutWidth - ClockStyle.gapTiny * 2
    readonly property int columns: root.compact ? 1 : Math.max(1, Math.floor((root.contentLayoutWidth + root.gap) / (VitalsStyle.tileMinWidth + root.gap)))
    readonly property real tileLayoutWidth: (root.contentLayoutWidth - root.gap * (root.columns - 1)) / root.columns
    readonly property real tileHeight: Math.round(Math.max(VitalsStyle.tileHeightMin, Math.min(VitalsStyle.tileHeightMax, root.tileLayoutWidth * VitalsStyle.tileRatio)))
    // The fortnight takes two columns, or the whole row when no tile would sit beside it.
    readonly property int fortnightSpan: Math.min(root.columns, Math.max(2, root.columns - root.tileKeys.length))

    function spanWidth(span: int): real {
        return Math.floor(root.tileLayoutWidth * span + root.gap * (span - 1));
    }

    StyledFlickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: grid.implicitHeight + ClockStyle.gapTiny + ClockStyle.fabClearance
        clip: true

        Flow {
            id: grid
            x: ClockStyle.gapTiny
            y: ClockStyle.gapTiny
            width: Math.max(root.contentWidth, root.contentLayoutWidth)
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

            // ── The chosen day ──────────────────────────────────────────
            Rectangle {
                id: dayPane
                visible: root.hasHeartRate
                width: root.spanWidth(root.columns)
                height: root.compact ? 320 : 360
                radius: VitalsStyle.radiusTile
                color: VitalsStyle.colTile

                Behavior on width {
                    enabled: !ClockStyle.reducedMotion
                    animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                }

                StaggeredEntrance {
                    index: 0
                    active: !ClockStyle.reducedMotion
                }

                ColumnLayout {
                    anchors {
                        fill: parent
                        margins: VitalsStyle.tilePadding
                    }
                    spacing: ClockStyle.gap

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapSmall

                        MaterialShapeWrappedMaterialSymbol {
                            text: "favorite"
                            iconSize: 18
                            padding: 9
                            shape: MaterialShape.Shape.Cookie9Sided
                            color: ClockStyle.colPrimaryContainer
                            colSymbol: ClockStyle.colOnPrimaryContainer
                            fill: 1
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: AppStats.periodLabel("day", root.dayOffset)
                                elide: Text.ElideRight
                                font.family: ClockStyle.fontTitle
                                font.variableAxes: ClockStyle.axesTitle
                                font.pixelSize: ClockStyle.textLarge
                                color: VitalsStyle.colOnTile
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: AppStats.periodRangeLabel("day", root.dayOffset)
                                elide: Text.ElideRight
                                font.pixelSize: ClockStyle.textSmall
                                color: VitalsStyle.colOnTileVariant
                            }
                        }

                        ClockCardAction {
                            symbol: "chevron_left"
                            tip: Translation.tr("Previous day")
                            enabled: root.chosenDate > root.oldest
                            onClicked: root.stepDay(-1)
                        }

                        ClockCardAction {
                            symbol: "chevron_right"
                            tip: Translation.tr("Next day")
                            enabled: root.chosenDate < root.today
                            onClicked: root.stepDay(1)
                        }

                        LimitsTintButton {
                            visible: root.chosenDate !== root.today
                            symbol: "today"
                            label: root.layoutWidth > 560 ? Translation.tr("Today") : ""
                            height_: 34
                            onClicked: root.chosenDate = root.today
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapLarge

                        UsageFigure {
                            visible: root.dayRange !== null
                            text: root.dayRange ? root.digits(root.dayRange[1]) + " " + VitalsTypes.info("heartRate").unit : ""
                            size: root.compact ? 44 : 56
                            color: VitalsStyle.colOnTile
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignBottom
                            Layout.bottomMargin: 6
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: root.dayRange ? Translation.tr("average · %1–%2 bpm").arg(root.digits(root.dayRange[0])).arg(root.digits(root.dayRange[2]))
                                    : Translation.tr("No heart rate this day")
                                elide: Text.ElideRight
                                font.pixelSize: ClockStyle.textNormal
                                font.weight: Font.DemiBold
                                color: VitalsStyle.colOnTile
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: root.dayRange !== null
                                text: Translation.tr("The band spans each %1 minutes' lowest to highest; click an hour for its readings").arg(root.binMin <= 1 ? 5 : 15)
                                elide: Text.ElideRight
                                font.pixelSize: ClockStyle.textSmall
                                color: VitalsStyle.colOnTileVariant
                            }
                        }
                    }

                    VitalsHeartDayChart {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        slots: root.slots
                        selectedHour: root.panels?.isShowing(hourSheet) && root.panels.current?.date === root.chosenDate ? root.panels.current.hour : -1
                        colLine: ClockStyle.colPrimary
                        colContent: VitalsStyle.colOnTile
                        emptyText: root.dayRange ? Translation.tr("Loading…") : Translation.tr("No heart rate this day")
                        onHourClicked: hour => root.openHour(hour)
                    }
                }
            }

            // ── The fortnight as range bars ─────────────────────────────
            Rectangle {
                id: fortnightPane
                visible: root.hasHeartRate
                width: root.spanWidth(root.fortnightSpan)
                height: root.tileHeight
                radius: VitalsStyle.radiusTile
                color: VitalsStyle.colTile

                Behavior on width {
                    enabled: !ClockStyle.reducedMotion
                    animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                }

                StaggeredEntrance {
                    index: 1
                    active: !ClockStyle.reducedMotion
                }

                ColumnLayout {
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
                            text: "date_range"
                            iconSize: ClockStyle.iconSmall + 2
                            fill: 1
                            color: VitalsStyle.colOnTile
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.fortnightEnd === root.today ? Translation.tr("Last 14 days")
                                : Translation.tr("14 days to %1").arg(VitalsFormat.dayLabel(root.fortnightEnd, root.now))
                            elide: Text.ElideRight
                            font.pixelSize: ClockStyle.textNormal
                            font.weight: Font.DemiBold
                            color: VitalsStyle.colOnTile
                        }

                        StyledText {
                            text: Translation.tr("lowest to highest, notch = average")
                            visible: fortnightPane.width > 420
                            font.pixelSize: ClockStyle.textSmall
                            color: VitalsStyle.colOnTileVariant
                            opacity: 0.8
                        }
                    }

                    VitalsGenericRangeBars {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        ranges: root.fortnightRanges
                        labels: root.fortnight.map(d => String(Number(d.slice(8, 10))))
                        tooltipLabels: root.fortnight.map(d => VitalsFormat.dayLabel(d, root.now))
                        selectedIndex: root.fortnight.indexOf(root.chosenDate)
                        colBar: ClockStyle.colPrimary
                        colContent: VitalsStyle.colOnTile
                        colPane: VitalsStyle.colTile
                        emptyText: Translation.tr("No heart rate in these 14 days")
                        onBarClicked: index => root.chosenDate = root.fortnight[index]
                    }
                }
            }

            // ── Other heart types: newest reading and a month's trend ───
            Repeater {
                model: ScriptModel {
                    values: root.tileKeys
                }

                VitalsTile {
                    id: tile
                    required property var modelData
                    required property int index
                    readonly property string key: String(tile.modelData)
                    readonly property var info: VitalsTypes.info(tile.key)
                    /// What a day's value is for the trend: the measurement's main field, else the key.
                    readonly property string seriesKey: tile.info.kind === "measurements" && tile.info.primary ? tile.key + "." + tile.info.primary : tile.key
                    readonly property var last: {
                        VitalsService.dataVersion;
                        return VitalsService.latest(tile.key);
                    }
                    // Daily types keep their calendar (a missed day is a gap); occasional
                    // measurements are joined reading to reading, else each would be an island.
                    readonly property var trend: {
                        VitalsService.dataVersion;
                        const from = VitalsFormat.addDays(root.today, -29);
                        const points = VitalsService.series(tile.seriesKey, from, root.today);
                        if (tile.info.kind === "measurements")
                            return points.map(p => p.value);
                        const byDate = {};
                        for (const p of points)
                            byDate[p.date] = p.value;
                        return Array.from({ length: 30 }, (_, i) => byDate[VitalsFormat.addDays(from, i)] ?? null);
                    }
                    readonly property var known: tile.trend.filter(v => v !== null)
                    readonly property string shownValue: {
                        if (!tile.last)
                            return "";
                        if (tile.key === "bloodPressure" && typeof tile.last.value === "object")
                            return root.digits(tile.last.value.systolic) + "/" + root.digits(tile.last.value.diastolic);
                        return tile.info.kind === "measurements" && tile.info.primary
                            ? Number(tile.last.value?.[tile.info.primary]).toLocaleString(Qt.locale(), "f", 1)
                            : Number(tile.last.value).toLocaleString(Qt.locale(), "f", 0);
                    }

                    /// "51–58 bpm": the month's lowest and highest daily value, the unit once.
                    readonly property string trendRange: {
                        if (tile.known.length < 2)
                            return "";
                        const decimals = tile.info.kind === "measurements" && tile.key !== "bloodPressure" ? 1 : 0;
                        const lo = Number(Math.min(...tile.known)).toLocaleString(Qt.locale(), "f", decimals);
                        const hi = Number(Math.max(...tile.known)).toLocaleString(Qt.locale(), "f", decimals);
                        const span = lo === hi ? lo : lo + "–" + hi;
                        return tile.key === "bloodPressure" ? Translation.tr("systolic %1").arg(span) : span + " " + tile.info.unit;
                    }

                    width: Math.floor(root.tileLayoutWidth)
                    height: root.tileHeight
                    entranceIndex: 2 + tile.index
                    symbol: tile.info.icon
                    title: tile.info.label
                    asOf: tile.last ? VitalsFormat.asOf(tile.last.time, tile.last.date, root.now) : ""
                    emphasis: VitalsStyle.emphasis(tile.last?.date ?? "", root.today)
                    onClicked: {
                        if (root.hasHeartRate && tile.last)
                            root.chosenDate = tile.last.date;
                    }

                    Behavior on width {
                        enabled: !ClockStyle.reducedMotion
                        animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: ClockStyle.gapTiny

                        RowLayout {
                            spacing: ClockStyle.gapSmall

                            StyledText {
                                text: tile.shownValue
                                font.family: ClockStyle.fontMain
                                font.variableAxes: ClockStyle.axesDigits
                                font.pixelSize: Math.round(Math.min(48, tile.bodyHeight * 0.34))
                                color: tile.colContent
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignBottom
                                Layout.bottomMargin: 7
                                text: tile.info.unit
                                font.pixelSize: ClockStyle.textNormal
                                font.weight: Font.DemiBold
                                color: tile.colContentVariant
                            }
                        }

                        HealthSparkline {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: tile.known.length > 1
                            values: tile.trend
                            color: ClockStyle.colPrimary
                        }

                        Item {
                            Layout.fillHeight: true
                            visible: tile.known.length <= 1
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: tile.known.length > 1
                                ? Translation.tr("30 days: %1").arg(tile.trendRange)
                                : Translation.tr("No reading in the last 30 days")
                            elide: Text.ElideRight
                            font.pixelSize: ClockStyle.textSmall
                            color: tile.colContentVariant
                        }
                    }
                }
            }
        }
    }

    // ── An hour: its readings ───────────────────────────────────────────
    Component {
        id: hourSheet

        ClockSheet {
            id: sheet
            property string date: ""
            property int hour: 0
            property var day: null
            readonly property int binMin: sheet.day?.samples?.heartRate?.binMin ?? 1
            readonly property var readings: (sheet.day?.samples?.heartRate?.bins ?? []).filter(b => Math.floor(b[0] / 60) === sheet.hour)
            readonly property var values: sheet.readings.map(b => b[1])
            readonly property var slots: {
                const out = new Array(Math.ceil(60 / sheet.binMin)).fill(null);
                for (const b of sheet.readings)
                    out[Math.floor((b[0] % 60) / sheet.binMin)] = b[1];
                return out;
            }

            function load(): void {
                sheet.day = VitalsService.day(sheet.date);
            }

            function clock(minute: int): string {
                return String(Math.floor(minute / 60)).padStart(2, "0") + ":" + String(minute % 60).padStart(2, "0");
            }

            title: sheet.clock(sheet.hour * 60) + "–" + sheet.clock(((sheet.hour + 1) % 24) * 60)
            subtitle: VitalsFormat.dayLabel(sheet.date, root.now) + " · "
                + (sheet.binMin <= 1 ? Translation.tr("one reading a minute") : Translation.tr("one reading per %1 minutes").arg(sheet.binMin))
            Component.onCompleted: sheet.load()

            Connections {
                target: VitalsService
                function onDayLoaded(date) {
                    if (date === sheet.date)
                        sheet.load();
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: sheet.readings.length === 0
                text: sheet.day === null ? Translation.tr("Loading…") : Translation.tr("No readings in this hour")
                font.pixelSize: ClockStyle.textNormal
                color: ClockStyle.colSubtext
            }

            Rectangle {
                Layout.fillWidth: true
                visible: sheet.readings.length > 1
                implicitHeight: 128
                radius: ClockStyle.radiusSmall
                color: ClockStyle.colField

                // A few beats of margin, so a calm hour does not read as a jagged one.
                HealthSparkline {
                    anchors.fill: parent
                    anchors.margins: ClockStyle.gap
                    values: sheet.slots
                    minValue: Math.min(...sheet.values) - 8
                    maxValue: Math.max(...sheet.values) + 8
                    color: ClockStyle.colPrimary
                }
            }

            VitalsFactRow {
                visible: sheet.values.length > 0
                symbol: "arrow_downward"
                shapeKind: MaterialShape.Shape.Cookie7Sided
                caption: Translation.tr("Lowest")
                value: sheet.values.length > 0 ? VitalsTypes.format("heartRate", Math.min(...sheet.values)) : ""
            }

            VitalsFactRow {
                visible: sheet.values.length > 0
                symbol: "favorite"
                shapeKind: MaterialShape.Shape.Clover4Leaf
                caption: Translation.tr("Average")
                value: sheet.values.length > 0 ? VitalsTypes.format("heartRate", sheet.values.reduce((a, b) => a + b, 0) / sheet.values.length) : ""
            }

            VitalsFactRow {
                visible: sheet.values.length > 0
                symbol: "arrow_upward"
                shapeKind: MaterialShape.Shape.Sunny
                caption: Translation.tr("Highest")
                value: sheet.values.length > 0 ? VitalsTypes.format("heartRate", Math.max(...sheet.values)) : ""
            }

            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: ClockStyle.gapSmall
                visible: sheet.readings.length > 0
                text: Translation.tr("%1 readings").arg(sheet.readings.length)
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Bold
                color: ClockStyle.colOnSurfaceVariant
            }

            // Every reading, time and value, read down the columns.
            Rectangle {
                Layout.fillWidth: true
                visible: sheet.readings.length > 0
                implicitHeight: readingGrid.implicitHeight + ClockStyle.gap * 2
                radius: ClockStyle.radiusSmall
                color: ClockStyle.colField

                GridLayout {
                    id: readingGrid
                    anchors {
                        fill: parent
                        margins: ClockStyle.gap
                    }
                    flow: GridLayout.TopToBottom
                    columns: 3
                    rows: Math.ceil(sheet.readings.length / 3)
                    columnSpacing: ClockStyle.gapLarge
                    rowSpacing: 2

                    Repeater {
                        model: sheet.readings

                        RowLayout {
                            id: reading
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: ClockStyle.gapSmall

                            StyledText {
                                text: sheet.clock(reading.modelData[0])
                                font.pixelSize: ClockStyle.textSmall
                                color: ClockStyle.colOnSurfaceVariant
                            }

                            StyledText {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignRight
                                text: root.digits(reading.modelData[1])
                                font.pixelSize: ClockStyle.textSmall
                                font.weight: Font.Bold
                                color: ClockStyle.colOnSurface
                            }
                        }
                    }
                }
            }
        }
    }
}
