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
import qs.modules.ii.vitals.components

/**
 * Activity: a day, week or month of movement, walked with Usage's period controls. Steps
 * lead on the primary pane: a day by the hour, longer periods by the day against the goal
 * line. Below, one short tile per other activity type with a value for the period and,
 * over several days, its trend. Any day opens a sheet with its hours and totals.
 */
VitalsPage {
    id: root

    // ── Period (calendar days, weeks and months, as in Usage) ───────────
    property string granularity: "day"
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
    readonly property var present: VitalsService.present
    readonly property var goals: VitalsService.meta?.goals ?? ({})
    readonly property var activityKeys: VitalsTypes.keysFor("activity", root.present)
    /// The type the pane leads with: steps, or the first activity type there is.
    readonly property string heroKey: root.present.steps ? "steps" : (root.activityKeys[0] ?? "steps")
    readonly property var tileKeys: root.activityKeys.filter(k => k !== root.heroKey)
    readonly property var rows: {
        VitalsService.dataVersion;
        return root.dates.map(d => VitalsService.summary(d));
    }
    readonly property var heroValues: root.rows.map(r => root.valueOf(r, root.heroKey) ?? 0)
    readonly property var heroDays: root.rows.filter(r => root.valueOf(r, root.heroKey) !== undefined)
    readonly property real heroTotal: root.heroValues.reduce((a, b) => a + b, 0)
    readonly property real heroGoal: Number(root.goals[root.heroKey]) || 0
    readonly property int goalDays: root.heroGoal > 0 ? root.heroValues.filter(v => v >= root.heroGoal).length : 0
    /// The chosen day's hourly values for the lead type (from its day file), or null.
    property var hourly: null

    function valueOf(row: var, key: string): var {
        return row?.t?.[key] ?? row?.sc?.[key];
    }

    function refresh(): void {
        root.hourly = root.isDay && root.dates.length > 0
            ? (VitalsService.day(root.dates[0])?.totals?.[root.heroKey]?.hourly ?? null) : null;
    }

    function stepPeriod(delta: int): void {
        if ((delta < 0 && !root.canGoBack) || (delta > 0 && root.periodOffset >= 0))
            return;
        root.periodOffset += delta;
    }

    function setGranularity(key: string): void {
        root.granularity = key;
        root.periodOffset = 0;
    }

    function openDay(date: string): void {
        if (date !== "")
            root.panels.show(daySheet, { date: date });
    }

    /// The newest day of the period that has the key, else its last day.
    function lastDayWith(key: string): string {
        for (let i = root.rows.length - 1; i >= 0; i--)
            if (root.valueOf(root.rows[i], key) !== undefined)
                return root.dates[i];
        return root.dates[root.dates.length - 1] ?? "";
    }

    function digits(v: real): string {
        return Number(v).toLocaleString(Qt.locale(), "f", 0);
    }

    Component.onCompleted: root.refresh()
    onDatesChanged: Qt.callLater(root.refresh)

    Connections {
        target: VitalsService
        function onDataVersionChanged() {
            root.refresh();
        }
        function onDayLoaded(date) {
            if (root.isDay && date === root.dates[0])
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
        if (key === Qt.Key_Return || key === Qt.Key_Enter) {
            root.openDay(root.lastDayWith(root.heroKey));
            return true;
        }
        return false;
    }

    // ── Layout ──────────────────────────────────────────────────────────
    readonly property real gap: ClockStyle.gap
    readonly property real contentWidth: root.width - ClockStyle.gapTiny * 2
    readonly property real contentLayoutWidth: root.layoutWidth - ClockStyle.gapTiny * 2
    // Rows as even as the count allows: six tiles deal 3 + 3, not 4 + 2.
    readonly property int maxColumns: root.compact ? 1 : Math.max(1, Math.floor((root.contentLayoutWidth + root.gap) / (240 + root.gap)))
    readonly property int tileColumns: {
        const n = Math.max(1, root.tileKeys.length);
        return Math.ceil(n / Math.ceil(n / root.maxColumns));
    }
    readonly property real tileWidth: Math.floor((root.contentLayoutWidth - root.gap * (root.tileColumns - 1)) / root.tileColumns)

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

            // ── The lead type on the primary pane ───────────────────────
            Rectangle {
                id: hero
                readonly property color colPane: ClockStyle.colPrimary
                readonly property color colContent: ClockStyle.colOnPrimary
                readonly property int figureSize: Math.round(Math.max(44, Math.min(76, root.layoutWidth * 0.07)))

                Layout.fillWidth: true
                implicitHeight: heroColumn.implicitHeight + (ClockStyle.cardPadding + 4) * 2
                radius: ClockStyle.radiusCard
                color: hero.colPane

                StaggeredEntrance {
                    index: 0
                    active: !ClockStyle.reducedMotion
                }

                ColumnLayout {
                    id: heroColumn
                    anchors {
                        fill: parent
                        margins: ClockStyle.cardPadding + 4
                    }
                    spacing: ClockStyle.gap

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapSmall + 2

                        MaterialShapeWrappedMaterialSymbol {
                            text: VitalsTypes.icon(root.heroKey)
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
                                text: VitalsTypes.label(root.heroKey)
                                elide: Text.ElideRight
                                font.pixelSize: ClockStyle.textNormal + 1
                                font.weight: Font.DemiBold
                                color: hero.colContent
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: AppStats.periodRangeLabel(root.granularity, root.periodOffset)
                                elide: Text.ElideRight
                                font.pixelSize: ClockStyle.textSmall
                                color: hero.colContent
                                opacity: 0.8
                            }
                        }
                    }

                    // The one number: the day's total, or a day's average over longer periods.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapLarge

                        UsageFigure {
                            readonly property real shown: root.isDay ? root.heroTotal : root.heroTotal / Math.max(1, root.heroDays.length)
                            visible: root.heroDays.length > 0
                            text: root.heroKey === "steps"
                                ? root.digits(shown) + " " + VitalsTypes.info("steps").unit
                                : VitalsTypes.format(root.heroKey, shown)
                            size: hero.figureSize
                            color: hero.colContent
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignBottom
                            Layout.bottomMargin: Math.round(hero.figureSize * 0.12)
                            spacing: 2

                            StyledText {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: {
                                    // The chart below already says the period is empty.
                                    if (root.heroDays.length === 0)
                                        return "";
                                    if (root.isDay)
                                        return root.heroGoal > 0 ? Translation.tr("of %1").arg(VitalsTypes.format(root.heroKey, root.heroGoal)) : "";
                                    return Translation.tr("a day on average · %1 in all").arg(VitalsTypes.format(root.heroKey, root.heroTotal));
                                }
                                elide: Text.ElideRight
                                font.pixelSize: ClockStyle.textLarge
                                font.weight: Font.DemiBold
                                color: hero.colContent
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: root.heroGoal > 0 && root.heroDays.length > 0
                                text: root.isDay
                                    ? (root.heroTotal >= root.heroGoal ? Translation.tr("Goal reached")
                                        : Translation.tr("Goal at %1 %").arg(Math.round(root.heroTotal / root.heroGoal * 100)))
                                    : Translation.tr("Goal reached on %1 of %2 days").arg(root.goalDays).arg(root.dates.length)
                                elide: Text.ElideRight
                                font.pixelSize: ClockStyle.textNormal
                                color: hero.colContent
                                opacity: 0.85
                            }
                        }
                    }

                    UsagePeriodControls {
                        Layout.fillWidth: true
                        granularity: root.granularity
                        periodOffset: root.periodOffset
                        canGoBack: root.canGoBack
                        colContent: hero.colContent
                        colPane: hero.colPane
                        onGranularityPicked: key => root.setGranularity(key)
                        onStepped: delta => root.stepPeriod(delta)
                        onPeriodReset: root.periodOffset = 0
                    }

                    UsageHistogram {
                        id: histogram
                        // The phone's day can run ahead of the PC's clock (another zone), so "now"
                        // is never before the last hour that has data.
                        readonly property real hourNow: Math.max(new Date(root.now).getHours(),
                            (root.hourly ?? []).reduce((last, v, h) => v > 0 ? h : last, -1))
                        readonly property bool showGoal: !root.isDay && root.heroGoal > 0 && histogram.hasData

                        Layout.fillWidth: true
                        Layout.preferredHeight: root.compact ? 150 : 180
                        values: root.isDay ? (root.hourly ?? (root.heroTotal > 0 ? [] : new Array(24).fill(0))) : root.heroValues
                        labels: root.isDay
                            ? Array.from({ length: 24 }, (_, h) => String(h).padStart(2, "0"))
                            : root.dates.map(d => root.granularity === "week"
                                ? Qt.locale().toString(new Date(Number(d.slice(0, 4)), Number(d.slice(5, 7)) - 1, Number(d.slice(8, 10))), "ddd")
                                : String(Number(d.slice(8, 10))))
                        tooltipLabels: root.isDay
                            ? Array.from({ length: 24 }, (_, h) => String(h).padStart(2, "0") + ":00–" + String((h + 1) % 24).padStart(2, "0") + ":00")
                            : root.dates.map(d => VitalsFormat.dayLabel(d, root.now))
                        nowIndex: root.isDay ? (root.dates[0] === root.today ? histogram.hourNow : -1) : root.dates.indexOf(root.today)
                        trimFuture: root.isDay
                        focusedIndex: !root.isDay && root.panels?.isShowing(daySheet) ? root.dates.indexOf(root.panels.current?.date ?? "") : -1
                        labelStride: root.isDay ? 3 : 1
                        labelAnchorEnd: !root.isDay
                        axisCeiling: histogram.showGoal
                            ? Math.ceil(Math.max(root.heroGoal, ...root.heroValues) / histogram.niceStep(Math.max(root.heroGoal, ...root.heroValues) / 2))
                                * histogram.niceStep(Math.max(root.heroGoal, ...root.heroValues) / 2)
                            : 0
                        emphasisAt: histogram.showGoal ? (i => root.heroValues[i] >= root.heroGoal ? 0.95 : 0.5) : null
                        formatValue: v => VitalsTypes.format(root.heroKey, v)
                        formatTick: v => v >= 1000 && root.heroKey === "steps" ? Translation.tr("%1k").arg(Number(v / 1000).toLocaleString(Qt.locale(), "f", v % 1000 === 0 ? 0 : 1)) : VitalsTypes.format(root.heroKey, v)
                        emptyText: root.isDay && root.heroTotal > 0
                            ? Translation.tr("No hourly breakdown for this day")
                            : Translation.tr("No %1 %2").arg(VitalsTypes.label(root.heroKey).toLowerCase()).arg(root.periodWord)
                        colContent: hero.colContent
                        colPane: hero.colPane
                        onBarClicked: index => root.openDay(root.isDay ? root.dates[0] : root.dates[index])

                        // The goal across the days, drawn over the bars it measures.
                        Rectangle {
                            visible: histogram.showGoal
                            y: Math.round(histogram.plotHeight * (1 - root.heroGoal / Math.max(1, histogram.axisMax))) - 1
                            width: histogram.plotWidth
                            height: 2
                            radius: 1
                            color: ColorUtils.applyAlpha(hero.colContent, 0.7)

                            Rectangle {
                                anchors.left: parent.left
                                anchors.bottom: parent.top
                                anchors.bottomMargin: 3
                                width: goalLabel.implicitWidth + ClockStyle.gapSmall * 2
                                height: goalLabel.implicitHeight + 4
                                radius: ClockStyle.pill(height)
                                color: hero.colPane

                                StyledText {
                                    id: goalLabel
                                    anchors.centerIn: parent
                                    text: Translation.tr("Goal %1").arg(VitalsTypes.format(root.heroKey, root.heroGoal))
                                    font.pixelSize: ClockStyle.textSmall
                                    font.weight: Font.Bold
                                    color: hero.colContent
                                }
                            }
                        }
                    }
                }
            }

            // ── The other activity types ────────────────────────────────
            Flow {
                Layout.fillWidth: true
                visible: root.tileKeys.length > 0
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
                        values: root.tileKeys
                    }

                    VitalsTile {
                        id: tile
                        required property var modelData
                        required property int index
                        readonly property string key: String(tile.modelData)
                        readonly property bool isScore: VitalsTypes.info(tile.key).kind === "scores"
                        readonly property var values: root.rows.map(r => root.valueOf(r, tile.key) ?? null)
                        readonly property var known: tile.values.filter(v => v !== null)
                        readonly property real total: tile.known.reduce((a, b) => a + b, 0)
                        readonly property real goal: Number(root.goals[tile.key]) || 0
                        // Scores average; amounts add up over a period.
                        readonly property string shown: tile.known.length === 0 ? ""
                            : VitalsTypes.format(tile.key, tile.isScore && !root.isDay ? tile.total / tile.known.length : tile.total)
                        readonly property string caption: {
                            if (tile.known.length === 0)
                                return Translation.tr("No data %1").arg(root.periodWord);
                            if (root.isDay)
                                return tile.goal > 0 ? Translation.tr("of %1 goal").arg(VitalsTypes.format(tile.key, tile.goal)) : "";
                            return tile.isScore ? Translation.tr("average over %1 days").arg(tile.known.length)
                                : Translation.tr("%1 a day").arg(VitalsTypes.format(tile.key, tile.total / tile.known.length));
                        }

                        width: root.tileWidth
                        height: 124
                        entranceIndex: 1 + tile.index
                        symbol: VitalsTypes.icon(tile.key)
                        title: VitalsTypes.label(tile.key)
                        onClicked: root.openDay(root.lastDayWith(tile.key))

                        Behavior on width {
                            enabled: !ClockStyle.reducedMotion
                            animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                        }

                        RowLayout {
                            anchors.fill: parent
                            spacing: ClockStyle.gapLarge

                            ColumnLayout {
                                Layout.alignment: Qt.AlignBottom
                                Layout.maximumWidth: tile.bodyWidth * (spark.visible ? 0.55 : 1)
                                spacing: 0

                                StyledText {
                                    Layout.fillWidth: true
                                    visible: tile.shown.length > 0
                                    text: tile.shown
                                    elide: Text.ElideRight
                                    font.family: ClockStyle.fontMain
                                    font.variableAxes: ClockStyle.axesDigits
                                    font.pixelSize: 30
                                    color: tile.colContent
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    visible: text.length > 0
                                    text: tile.caption
                                    elide: Text.ElideRight
                                    font.pixelSize: ClockStyle.textSmall
                                    color: tile.colContentVariant
                                    opacity: tile.known.length === 0 ? 0.8 : 1
                                }
                            }

                            // A period's trend; a single day has none, so the space stays empty.
                            HealthSparkline {
                                id: spark
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.topMargin: ClockStyle.gapTiny
                                visible: !root.isDay && tile.known.length > 1
                                values: tile.values
                                color: ClockStyle.colPrimary
                            }
                        }
                    }
                }
            }
        }
    }

    // ── A day: its hours and totals ─────────────────────────────────────
    Component {
        id: daySheet

        ClockSheet {
            id: sheet
            property string date: ""
            property var day: null
            readonly property var summary: {
                VitalsService.dataVersion;
                return VitalsService.summary(sheet.date);
            }
            readonly property var keys: root.activityKeys.filter(k => root.valueOf(sheet.summary, k) !== undefined)
            readonly property var hours: {
                const h = sheet.day?.totals?.[root.heroKey]?.hourly ?? null;
                if (!h)
                    return [];
                const out = [];
                for (let i = 0; i < 24; i++)
                    if (h[i] > 0)
                        out.push({ hour: i, value: h[i] });
                return out;
            }
            readonly property real hourMax: Math.max(1, ...sheet.hours.map(h => h.value))
            readonly property var shapes: [MaterialShape.Shape.Cookie12Sided, MaterialShape.Shape.Clover4Leaf,
                MaterialShape.Shape.Cookie7Sided, MaterialShape.Shape.Sunny, MaterialShape.Shape.Cookie9Sided,
                MaterialShape.Shape.SoftBurst, MaterialShape.Shape.Flower, MaterialShape.Shape.Cookie6Sided]

            function load(): void {
                sheet.day = VitalsService.day(sheet.date);
            }

            title: {
                const d = new Date(Number(sheet.date.slice(0, 4)), Number(sheet.date.slice(5, 7)) - 1, Number(sheet.date.slice(8, 10)));
                return Qt.locale().toString(d, "dddd d MMMM");
            }
            subtitle: VitalsFormat.dayLabel(sheet.date, root.now)
            Component.onCompleted: sheet.load()

            Connections {
                target: VitalsService
                function onDayLoaded(date) {
                    if (date === sheet.date)
                        sheet.load();
                }
            }

            Repeater {
                model: ScriptModel {
                    values: sheet.keys
                }

                VitalsFactRow {
                    required property var modelData
                    required property int index
                    symbol: VitalsTypes.icon(String(modelData))
                    shapeKind: sheet.shapes[index % sheet.shapes.length]
                    caption: VitalsTypes.label(String(modelData))
                    value: {
                        const v = root.valueOf(sheet.summary, String(modelData));
                        const goal = Number(root.goals[String(modelData)]) || 0;
                        return VitalsTypes.format(String(modelData), v)
                            + (goal > 0 ? "  ·  " + Translation.tr("%1 % of goal").arg(Math.round(v / goal * 100)) : "");
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: ClockStyle.gapSmall
                text: Translation.tr("%1 by the hour").arg(VitalsTypes.label(root.heroKey))
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Bold
                color: ClockStyle.colOnSurfaceVariant
            }

            StyledText {
                Layout.fillWidth: true
                visible: sheet.hours.length === 0
                text: sheet.day === null && sheet.summary !== null ? Translation.tr("Loading…") : Translation.tr("No hourly breakdown for this day")
                wrapMode: Text.WordWrap
                font.pixelSize: ClockStyle.textNormal
                color: ClockStyle.colSubtext
            }

            Rectangle {
                Layout.fillWidth: true
                visible: sheet.hours.length > 0
                implicitHeight: hourColumn.implicitHeight + ClockStyle.gap * 2
                radius: ClockStyle.radiusSmall
                color: ClockStyle.colField

                ColumnLayout {
                    id: hourColumn
                    anchors {
                        fill: parent
                        margins: ClockStyle.gap
                    }
                    spacing: ClockStyle.gapSmall

                    Repeater {
                        model: sheet.hours

                        RowLayout {
                            id: hourRow
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: ClockStyle.gapSmall

                            StyledText {
                                Layout.preferredWidth: 44
                                text: String(hourRow.modelData.hour).padStart(2, "0") + ":00"
                                font.pixelSize: ClockStyle.textSmall
                                font.weight: Font.Medium
                                color: ClockStyle.colOnSurfaceVariant
                            }

                            Item {
                                Layout.fillWidth: true
                                implicitHeight: 10

                                Rectangle {
                                    width: Math.max(height, parent.width * hourRow.modelData.value / sheet.hourMax)
                                    height: parent.height
                                    radius: height / 2
                                    color: ClockStyle.colPrimary
                                }
                            }

                            StyledText {
                                Layout.preferredWidth: 60
                                horizontalAlignment: Text.AlignRight
                                text: VitalsTypes.format(root.heroKey, hourRow.modelData.value)
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
