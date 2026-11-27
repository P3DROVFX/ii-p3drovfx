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
import qs.modules.ii.vitals.components

/**
 * Today: steps against the goal as the hero, then one tile per type, each in its own
 * technique so no two read alike (wavy progress, stage strip, sparkline, a number in a
 * scalloped shape, the title face, wide display digits, negative space). A tile shows
 * the newest value with when it is from; data weeks old stays, with less weight. Types
 * without a tile of their own get the generic one when they have a value today. Every
 * tile opens its type's page.
 */
VitalsPage {
    id: root

    // ── Grid ────────────────────────────────────────────────────────────
    readonly property real gridGap: ClockStyle.gap
    readonly property real contentWidth: root.width - ClockStyle.gapTiny * 2
    readonly property real contentLayoutWidth: root.layoutWidth - ClockStyle.gapTiny * 2
    readonly property int columns: Math.max(1, Math.floor((root.contentLayoutWidth + root.gridGap) / (VitalsStyle.tileMinWidth + root.gridGap)))
    readonly property real tileLayoutWidth: (root.contentLayoutWidth - root.gridGap * (root.columns - 1)) / root.columns
    readonly property real tileWidth: Math.floor(root.tileLayoutWidth)
    readonly property real tileHeight: Math.round(Math.max(VitalsStyle.tileHeightMin, Math.min(VitalsStyle.tileHeightMax, root.tileLayoutWidth * VitalsStyle.tileRatio)))
    readonly property int heroSpan: Math.min(VitalsStyle.heroSpan, root.columns)

    // ── Data ────────────────────────────────────────────────────────────
    readonly property string today: VitalsFormat.dateOf(root.now)
    readonly property var present: VitalsService.present
    readonly property var summary: {
        VitalsService.dataVersion;
        return VitalsService.summary(root.today);
    }
    readonly property var goals: VitalsService.meta?.goals ?? ({})

    readonly property real steps: root.summary?.t?.steps ?? 0
    readonly property real stepGoal: Number(root.goals.steps) || 0
    readonly property real stepProgress: root.stepGoal > 0 ? root.steps / root.stepGoal : 0

    // What needs a day file (stages, heart bins, sessions) is gathered by refresh(), which
    // runs again as each file lands.
    property var heart: null
    property var heartBins: []
    property var sleep: null
    property string sleepDate: ""
    property var workout: null
    property string workoutDate: ""

    readonly property var energy: {
        VitalsService.dataVersion;
        return root.present.energy ? VitalsService.latest("energy") : null;
    }
    readonly property string skinKey: root.present.skinTempC ? "skinTempC" : root.present.skinTempDeltaC ? "skinTempDeltaC" : ""
    readonly property var skin: {
        VitalsService.dataVersion;
        if (root.skinKey === "")
            return null;
        const l = VitalsService.latest(root.skinKey);
        if (!l)
            return null;
        const night = VitalsService.summary(l.date)?.s?.[root.skinKey]?.[1] ?? l.value;
        if (root.skinKey === "skinTempDeltaC")
            return { date: l.date, time: l.time, value: night, delta: Math.round(night * 10) / 10, nights: 0 };
        const base = VitalsService.series(root.skinKey, VitalsFormat.addDays(l.date, -14), VitalsFormat.addDays(l.date, -1)).map(p => p.value);
        const mean = base.length > 0 ? base.reduce((a, b) => a + b, 0) / base.length : NaN;
        // Rounded first, so a change too small to show reads 0.0 rather than −0.0.
        return { date: l.date, time: l.time, value: night, delta: Math.round((night - mean) * 10) / 10, nights: base.length };
    }
    readonly property var body: {
        VitalsService.dataVersion;
        return root.present.body ? VitalsService.latest("body") : null;
    }

    // Shown by a tile of their own (or inside the hero), so never by the generic one.
    readonly property var ownTiles: ["steps", "distanceM", "floors", "activeMin", "activeKcal", "sleep", "heartRate",
        "energy", "exercise", "skinTempC", "skinTempDeltaC", "body"]
    readonly property var genericKeys: {
        VitalsService.dataVersion;
        const out = [];
        for (const pageName of VitalsTypes.pages) {
            for (const key of VitalsTypes.keysFor(pageName, root.present)) {
                if (root.ownTiles.includes(key))
                    continue;
                if (VitalsTypes.info(key).kind === "sessions" ? (root.summary?.n?.[key] ?? 0) > 0 : VitalsService.latest(key)?.date === root.today)
                    out.push(key);
            }
        }
        return out;
    }

    function refresh(): void {
        const hr = root.present.heartRate ? VitalsService.latest("heartRate") : null;
        root.heart = hr;
        root.heartBins = hr ? root.slots(VitalsService.day(hr.date)?.samples?.heartRate?.bins ?? [], hr.date === root.today ? hr.time : 0) : [];

        let sleepDate = root.today;
        let s = root.present.sleep ? VitalsService.sleepFor(sleepDate) : null;
        if (root.present.sleep && !s) {
            sleepDate = VitalsService.latest("sleep")?.date ?? "";
            s = sleepDate !== "" ? VitalsService.sleepFor(sleepDate) : null;
        }
        root.sleepDate = s ? sleepDate : "";
        root.sleep = s;

        const ex = root.present.exercise ? VitalsService.latest("exMin") : null;
        root.workoutDate = ex?.date ?? "";
        const sessions = ex ? (VitalsService.day(ex.date)?.sessions?.exercise ?? []) : [];
        root.workout = sessions.length > 0 ? sessions.reduce((a, b) => (b.start > a.start ? b : a)) : null;
    }

    /// Heart bins ([[minute, bpm], …]) as one mean per 10 minutes, null where there is
    /// none, up to `until` (ms) today or the whole day before.
    function slots(bins: var, until: real): var {
        const last = until > 0 ? Math.floor((new Date(until).getHours() * 60 + new Date(until).getMinutes()) / 10) : 143;
        const sum = new Array(last + 1).fill(0), n = new Array(last + 1).fill(0);
        for (const b of bins) {
            const i = Math.floor(b[0] / 10);
            if (i <= last) {
                sum[i] += b[1];
                n[i]++;
            }
        }
        return sum.map((s, i) => n[i] > 0 ? s / n[i] : null);
    }

    Component.onCompleted: root.refresh()
    onTodayChanged: root.refresh()

    Connections {
        target: VitalsService
        function onDataVersionChanged() {
            root.refresh();
        }
        function onDayLoaded(date) {
            if (date === root.today || date === root.heart?.date || date === root.sleepDate || date === root.workoutDate)
                root.refresh();
        }
    }

    pageSubtitle: {
        const parts = [];
        if (!VitalsService.linked)
            parts.push(Translation.tr("Phone away"));
        if (VitalsService.syncing)
            parts.push(VitalsService.progress > 0 ? Translation.tr("Syncing… %1 %").arg(Math.round(VitalsService.progress * 100)) : Translation.tr("Syncing…"));
        else if (VitalsService.lastSync > 0)
            parts.push(Translation.tr("Synced %1").arg(VitalsFormat.ago(VitalsService.lastSync, root.now)));
        if (root.heart?.time)
            parts.push(Translation.tr("heart rate as of %1").arg(VitalsFormat.asOf(root.heart.time, root.heart.date, root.now)));
        return parts.join(" · ");
    }

    // Nothing to sync with the phone away; while a sync runs, the subtitle and the rail say so.
    fab: VitalsService.linked && !VitalsService.syncing ? { symbol: "sync", label: Translation.tr("Sync now") } : null

    function fabTriggered(): void {
        VitalsService.syncNow();
    }

    function digits(v: real): string {
        return Number(v).toLocaleString(Qt.locale(), "f", 0);
    }

    /// "7h 32" for a night's length in minutes.
    function hoursMinutes(min: real): string {
        const m = Math.round(min);
        return Translation.tr("%1h %2").arg(Math.floor(m / 60)).arg(String(m % 60).padStart(2, "0"));
    }

    StyledFlickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: grid.implicitHeight + ClockStyle.gapTiny + ClockStyle.fabClearance
        clip: true

        // Every tile carries its own width, so a lone tile never swells to the row.
        Flow {
            id: grid
            x: ClockStyle.gapTiny
            y: ClockStyle.gapTiny
            width: Math.max(root.contentWidth, root.contentLayoutWidth)
            spacing: root.gridGap

            move: Transition {
                enabled: !ClockStyle.reducedMotion
                NumberAnimation {
                    properties: "x,y"
                    duration: ClockStyle.motionDefault.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: ClockStyle.motionDefault.bezierCurve
                }
            }

            // ── Steps (hero) ────────────────────────────────────────────
            VitalsTile {
                id: hero
                visible: root.present.steps === true
                width: Math.floor(root.tileLayoutWidth * root.heroSpan + root.gridGap * (root.heroSpan - 1))
                height: root.tileHeight
                hero: true
                entranceIndex: 0
                symbol: "directions_walk"
                title: VitalsTypes.label("steps")
                asOf: root.summary ? "" : Translation.tr("Nothing yet today")
                onClicked: root.pageRequested("activity")

                Behavior on width {
                    enabled: !ClockStyle.reducedMotion
                    animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                }

                readonly property real bottomRows: heroProgress.height + heroFooter.implicitHeight + ClockStyle.gapSmall * 2
                // The one number, as large as the space above the progress line allows.
                readonly property int digitSize: Math.round(Math.max(36, Math.min(
                    (hero.bodyHeight - hero.bottomRows) / 1.18,
                    hero.bodyWidth * 0.55 / (Math.max(3, root.digits(root.steps).length) * 0.46))))

                ColumnLayout {
                    anchors.fill: parent
                    spacing: ClockStyle.gapSmall

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: ClockStyle.gapLarge

                        StyledText {
                            Layout.alignment: Qt.AlignBottom
                            text: root.digits(root.steps)
                            font.family: ClockStyle.fontMain
                            font.variableAxes: ClockStyle.axesDigitsBold
                            font.pixelSize: hero.digitSize
                            color: hero.colContent
                        }

                        ColumnLayout {
                            Layout.alignment: Qt.AlignBottom
                            Layout.bottomMargin: Math.round(hero.digitSize * 0.14)
                            Layout.fillWidth: true
                            spacing: 2

                            StyledText {
                                Layout.fillWidth: true
                                visible: root.stepGoal > 0
                                text: Translation.tr("of %1").arg(root.digits(root.stepGoal))
                                elide: Text.ElideRight
                                font.pixelSize: ClockStyle.textLarge
                                font.weight: Font.DemiBold
                                color: hero.colContent
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: [
                                    root.summary?.t?.distanceM !== undefined ? VitalsTypes.format("distanceM", root.summary.t.distanceM) : "",
                                    root.summary?.t?.floors !== undefined ? Translation.tr("%1 floors").arg(root.digits(root.summary.t.floors)) : "",
                                    root.summary?.t?.activeKcal !== undefined ? VitalsTypes.format("activeKcal", root.summary.t.activeKcal) : ""
                                ].filter(s => s.length > 0).join(" · ")
                                elide: Text.ElideRight
                                font.pixelSize: ClockStyle.textNormal
                                color: hero.colContent
                                opacity: 0.85
                            }
                        }
                    }

                    StyledProgressBar {
                        id: heroProgress
                        Layout.fillWidth: true
                        Layout.preferredHeight: 6
                        visible: root.stepGoal > 0
                        value: Math.min(1, root.stepProgress)
                        valueBarHeight: 6
                        valueBarGap: 6
                        wavy: true
                        highlightColor: ClockStyle.colPrimary
                        trackColor: ColorUtils.mix(VitalsStyle.colHero, VitalsStyle.colOnHero, 0.8)
                    }

                    StyledText {
                        id: heroFooter
                        Layout.fillWidth: true
                        text: [
                            root.stepGoal > 0 ? (root.stepProgress >= 1 ? Translation.tr("Goal reached") : Translation.tr("Goal at %1 %").arg(Math.round(root.stepProgress * 100))) : "",
                            root.summary?.t?.activeMin !== undefined ? Translation.tr("%1 active").arg(VitalsTypes.duration(root.summary.t.activeMin)) : ""
                        ].filter(s => s.length > 0).join(" · ")
                        elide: Text.ElideRight
                        font.pixelSize: ClockStyle.textSmall
                        color: hero.colContent
                        opacity: 0.85
                    }
                }
            }

            // ── Last night (stage strip) ────────────────────────────────
            VitalsTile {
                id: sleepTile
                visible: root.sleep !== null
                width: root.tileWidth
                height: root.tileHeight
                entranceIndex: 1
                symbol: "bedtime"
                title: root.sleepDate === root.today ? Translation.tr("Last night") : Translation.tr("Sleep")
                asOf: root.sleepDate === root.today ? "" : VitalsFormat.dayLabel(root.sleepDate, root.now)
                emphasis: VitalsStyle.emphasis(root.sleepDate, root.today)
                onClicked: root.pageRequested("sleep")

                readonly property var sleepGoal: root.goals.sleep ?? null

                ColumnLayout {
                    anchors.fill: parent
                    spacing: ClockStyle.gapSmall

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: ClockStyle.gap

                        StyledText {
                            Layout.alignment: Qt.AlignBottom
                            text: root.sleep ? root.hoursMinutes(root.sleep.min) : ""
                            font.family: ClockStyle.fontMain
                            font.variableAxes: ClockStyle.axesDigits
                            font.pixelSize: Math.round(Math.min(56, sleepTile.bodyHeight * 0.34))
                            color: sleepTile.colContent
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        ColumnLayout {
                            Layout.alignment: Qt.AlignBottom
                            Layout.bottomMargin: 6
                            visible: root.sleep?.score !== null && root.sleep?.score !== undefined
                            spacing: 0

                            StyledText {
                                Layout.alignment: Qt.AlignRight
                                text: Translation.tr("Score")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.Bold
                                color: sleepTile.colContentVariant
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignRight
                                text: String(root.sleep?.score ?? "")
                                font.pixelSize: ClockStyle.textLarge
                                font.weight: Font.Bold
                                color: sleepTile.colContent
                            }
                        }
                    }

                    VitalsStageStrip {
                        Layout.fillWidth: true
                        stages: root.sleep?.stages ?? null
                        minutes: root.sleep ? (root.sleep.end - root.sleep.start) / 60000 : 0
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.sleep
                            ? (VitalsFormat.clock(root.sleep.start) + " → " + VitalsFormat.clock(root.sleep.end)
                                + (sleepTile.sleepGoal?.bed && sleepTile.sleepGoal?.wake
                                    ? " · " + Translation.tr("goal %1 → %2").arg(sleepTile.sleepGoal.bed).arg(sleepTile.sleepGoal.wake) : ""))
                            : ""
                        elide: Text.ElideRight
                        font.pixelSize: ClockStyle.textSmall
                        color: sleepTile.colContentVariant
                    }
                }
            }

            // ── Heart rate (sparkline) ──────────────────────────────────
            VitalsTile {
                id: heartTile
                visible: root.heart !== null
                width: root.tileWidth
                height: root.tileHeight
                entranceIndex: 2
                symbol: "favorite"
                title: VitalsTypes.label("heartRate")
                asOf: root.heart ? VitalsFormat.asOf(root.heart.time, root.heart.date, root.now) : ""
                emphasis: VitalsStyle.emphasis(root.heart?.date ?? "", root.today)
                onClicked: root.pageRequested("heart")

                readonly property var range: {
                    VitalsService.dataVersion;
                    return root.heart ? (VitalsService.summary(root.heart.date)?.s?.heartRate ?? null) : null;
                }

                ColumnLayout {
                    anchors.fill: parent
                    spacing: ClockStyle.gapTiny

                    RowLayout {
                        spacing: ClockStyle.gapSmall

                        StyledText {
                            text: root.heart ? root.digits(root.heart.value) : ""
                            font.family: ClockStyle.fontMain
                            font.variableAxes: ClockStyle.axesDigitsBold
                            font.pixelSize: Math.round(Math.min(52, heartTile.bodyHeight * 0.36))
                            color: heartTile.colContent
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignBottom
                            Layout.bottomMargin: 8
                            text: Translation.tr("bpm")
                            font.pixelSize: ClockStyle.textNormal
                            font.weight: Font.DemiBold
                            color: heartTile.colContentVariant
                        }
                    }

                    HealthSparkline {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        values: root.heartBins
                        color: ClockStyle.colPrimary
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: heartTile.range !== null
                        text: heartTile.range
                            ? (root.heart.date === root.today ? Translation.tr("%1–%2 today") : Translation.tr("%1–%2 that day"))
                                .arg(root.digits(heartTile.range[0])).arg(root.digits(heartTile.range[2]))
                            : ""
                        elide: Text.ElideRight
                        font.pixelSize: ClockStyle.textSmall
                        color: heartTile.colContentVariant
                    }
                }
            }

            // ── Energy score (a number in a scalloped shape) ────────────
            VitalsTile {
                id: energyTile
                visible: root.energy !== null
                width: root.tileWidth
                height: root.tileHeight
                entranceIndex: 3
                symbol: "bolt"
                title: VitalsTypes.label("energy")
                asOf: root.energy ? VitalsFormat.dayLabel(root.energy.date, root.now) : ""
                emphasis: VitalsStyle.emphasis(root.energy?.date ?? "", root.today)
                onClicked: root.pageRequested("activity")

                readonly property real shapeSize: Math.round(Math.min(energyTile.bodyHeight, energyTile.bodyWidth * 0.7))

                MaterialShape {
                    anchors.centerIn: parent
                    width: energyTile.shapeSize
                    height: energyTile.shapeSize
                    shapeString: "Cookie12Sided"
                    color: ClockStyle.colTertiaryContainer
                }

                StyledText {
                    anchors.centerIn: parent
                    text: root.energy ? root.digits(root.energy.value) : ""
                    font.family: ClockStyle.fontMain
                    font.variableAxes: ClockStyle.axesDigitsBold
                    font.pixelSize: Math.round(energyTile.shapeSize * 0.4)
                    color: ClockStyle.colOnTertiaryContainer
                }
            }

            // ── Latest workout (the title face) ─────────────────────────
            VitalsTile {
                id: workoutTile
                visible: root.present.exercise === true && root.workoutDate !== ""
                width: root.tileWidth
                height: root.tileHeight
                entranceIndex: 4
                symbol: "exercise"
                title: Translation.tr("Latest workout")
                asOf: root.workout ? VitalsFormat.asOf(root.workout.start, root.workoutDate, root.now) : VitalsFormat.dayLabel(root.workoutDate, root.now)
                emphasis: VitalsStyle.emphasis(root.workoutDate, root.today)
                onClicked: root.pageRequested("workouts")

                readonly property var stats: {
                    const w = root.workout;
                    if (!w)
                        return [];
                    const out = [VitalsTypes.duration((w.end - w.start) / 60000)];
                    if (w.distanceM !== undefined)
                        out.push(VitalsTypes.format("distanceM", w.distanceM));
                    if (w.kcal !== undefined)
                        out.push(VitalsTypes.format("activeKcal", w.kcal));
                    if (w.hrAvg !== undefined)
                        out.push(Translation.tr("avg %1").arg(VitalsTypes.format("heartRate", w.hrAvg)));
                    return out;
                }

                ColumnLayout {
                    anchors.fill: parent
                    spacing: ClockStyle.gap

                    Rectangle {
                        implicitWidth: 48
                        implicitHeight: 48
                        radius: ClockStyle.radiusNormal
                        color: ClockStyle.colSecondaryContainer

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: VitalsTypes.exerciseIcon(root.workout?.type ?? "other")
                            iconSize: ClockStyle.iconNormal
                            fill: 1
                            color: ClockStyle.colOnSecondaryContainer
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        verticalAlignment: Text.AlignBottom
                        text: root.workout ? (root.workout.title ?? VitalsTypes.exerciseLabel(root.workout.type)) : ""
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        font.family: ClockStyle.fontTitle
                        font.variableAxes: ClockStyle.axesTitle
                        font.pixelSize: ClockStyle.textTitle + 2
                        color: workoutTile.colContent
                    }

                    StyledText {
                        id: workoutStats
                        Layout.fillWidth: true
                        text: workoutTile.stats.join(" · ")
                        elide: Text.ElideRight
                        font.pixelSize: ClockStyle.textNormal
                        color: workoutTile.colContentVariant

                        HoverHandler {
                            id: workoutStatsHover
                        }
                        StyledToolTip {
                            extraVisibleCondition: workoutStatsHover.hovered && workoutStats.truncated
                            text: workoutStats.text
                        }
                    }
                }
            }

            // ── Skin temperature (wide display digits) ──────────────────
            VitalsTile {
                id: skinTile
                visible: root.skin !== null
                width: root.tileWidth
                height: root.tileHeight
                entranceIndex: 5
                symbol: "thermostat"
                title: Translation.tr("Skin temp, night")
                asOf: root.skin ? VitalsFormat.dayLabel(root.skin.date, root.now) : ""
                emphasis: VitalsStyle.emphasis(root.skin?.date ?? "", root.today)
                onClicked: root.pageRequested("body")

                readonly property bool hasDelta: root.skin !== null && isFinite(root.skin.delta)

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 2

                    Item {
                        Layout.fillHeight: true
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.skin ? (skinTile.hasDelta ? VitalsTypes.format("skinTempDeltaC", root.skin.delta) : VitalsTypes.format("skinTempC", root.skin.value)) : ""
                        elide: Text.ElideRight
                        font.family: ClockStyle.fontMain
                        font.variableAxes: ClockStyle.axesDisplay
                        font.pixelSize: Math.round(Math.min(48, skinTile.bodyHeight * 0.34))
                        color: skinTile.colContent
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: skinTile.hasDelta && root.skinKey === "skinTempC"
                        text: Translation.tr("vs your %1-night baseline").arg(root.skin?.nights ?? 0)
                        elide: Text.ElideRight
                        font.pixelSize: ClockStyle.textNormal
                        color: skinTile.colContent
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: root.skinKey === "skinTempC"
                        text: root.skin ? Translation.tr("%1 that night").arg(VitalsTypes.format("skinTempC", root.skin.value)) : ""
                        elide: Text.ElideRight
                        font.pixelSize: ClockStyle.textSmall
                        color: skinTile.colContentVariant
                    }
                }
            }

            // ── Body (negative space) ───────────────────────────────────
            VitalsTile {
                id: bodyTile
                visible: root.body !== null
                width: root.tileWidth
                height: root.tileHeight
                entranceIndex: 6
                symbol: "monitor_weight"
                title: Translation.tr("Body")
                emphasis: VitalsStyle.emphasis(root.body?.date ?? "", root.today)
                onClicked: root.pageRequested("body")

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 2

                    Item {
                        Layout.fillHeight: true
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.body ? VitalsTypes.format("body", root.body.value) : ""
                        elide: Text.ElideRight
                        font.pixelSize: ClockStyle.textLarge
                        font.weight: Font.DemiBold
                        color: bodyTile.colContent
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.body ? Translation.tr("Last measured %1").arg(VitalsFormat.dayLabel(root.body.date, root.now)) : ""
                        elide: Text.ElideRight
                        font.pixelSize: ClockStyle.textNormal
                        color: bodyTile.colContentVariant
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Open Body for the history")
                        elide: Text.ElideRight
                        font.pixelSize: ClockStyle.textSmall
                        color: bodyTile.colContentVariant
                        opacity: 0.8
                    }
                }
            }

            // ── Everything else with a value today ──────────────────────
            Repeater {
                model: ScriptModel {
                    values: root.genericKeys
                }

                VitalsTile {
                    id: genericTile
                    required property var modelData
                    required property int index
                    readonly property string key: String(modelData)
                    readonly property var info: VitalsTypes.info(genericTile.key)
                    readonly property var last: {
                        VitalsService.dataVersion;
                        return genericTile.info.kind === "sessions" ? null : VitalsService.latest(genericTile.key);
                    }

                    width: root.tileWidth
                    // One value each: half a row, so two stack where a full tile would stand.
                    height: Math.round((root.tileHeight - root.gridGap) / 2)
                    entranceIndex: 7 + genericTile.index
                    symbol: genericTile.info.icon
                    title: genericTile.info.label
                    asOf: genericTile.last ? VitalsFormat.asOf(genericTile.last.time, genericTile.last.date, root.now) : ""
                    onClicked: root.pageRequested(genericTile.info.page)

                    StyledText {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        text: genericTile.info.kind === "sessions"
                            ? Translation.tr("%1 today").arg(root.digits(root.summary?.n?.[genericTile.key] ?? 0))
                            : VitalsTypes.format(genericTile.key, genericTile.last?.value)
                        elide: Text.ElideRight
                        font.pixelSize: ClockStyle.textTitle + 6
                        font.weight: Font.DemiBold
                        color: genericTile.colContent
                    }
                }
            }
        }
    }
}
