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
import qs.modules.ii.vitals.components

/**
 * Sleep: the chosen night (last night unless another is picked) as a large stage chart,
 * beside a ladder of every night from bed to wake on a 20:00–12:00 axis with the goal
 * window behind it. A night opens its sheet: the chart again, minutes per stage, score,
 * efficiency and the skin temperature of that night. ←/→ walk between nights.
 *
 * The ladder reads the index only (bed, wake, length, score per day), so every night is
 * there at no cost; only the chosen night's day file is read, for its stages.
 */
VitalsPage {
    id: root

    // ── Layout ──────────────────────────────────────────────────────────
    readonly property bool wide: !root.compact && root.layoutWidth >= 860
    readonly property real gap: ClockStyle.paneGap
    /// The stacked night pane's height; side by side it takes the page's.
    readonly property real stackedPaneHeight: 400

    // ── Data ────────────────────────────────────────────────────────────
    readonly property string today: VitalsFormat.dateOf(root.now)
    readonly property var goal: VitalsService.meta?.goals?.sleep ?? null

    /// Every night in the index, newest first.
    readonly property var nights: {
        VitalsService.dataVersion;
        const out = [];
        const dates = VitalsService.dates;
        for (let i = dates.length - 1; i >= 0; i--) {
            const s = VitalsService.summary(dates[i])?.sleep;
            if (s)
                out.push({ date: dates[i], start: s.start, end: s.end, min: s.min, score: s.score ?? null });
        }
        return out;
    }

    /// The ladder: the nights with a heading where the month changes.
    readonly property var ladder: {
        const out = [];
        let month = "";
        for (const n of root.nights) {
            if (n.date.slice(0, 7) !== month) {
                month = n.date.slice(0, 7);
                out.push({ key: "m" + month, heading: true, date: n.date });
            }
            out.push(Object.assign({ key: n.date, heading: false }, n));
        }
        return out;
    }

    property string selectedDate: ""
    readonly property int selectedIndex: root.nights.findIndex(n => n.date === root.selectedDate)
    /// sleepFor(selectedDate): stages arrive with the day file.
    property var night: null
    /// The chart grows in once per page; a layout switch rebuilds the pane settled.
    property bool grown: false

    function refresh(): void {
        // Not selectedIndex: inside onSelectedDateChanged that binding is still the old one.
        if (root.nights.length > 0 && !root.nights.some(n => n.date === root.selectedDate)) {
            root.selectedDate = root.nights[0].date;
            return;
        }
        root.night = root.selectedDate !== "" ? VitalsService.sleepFor(root.selectedDate) : null;
    }

    Component.onCompleted: root.refresh()
    onSelectedDateChanged: root.refresh()
    onWideChanged: Qt.callLater(() => ladderView.positionViewAtBeginning())

    Connections {
        target: VitalsService
        function onDataVersionChanged() {
            root.refresh();
        }
        function onDayLoaded(date) {
            if (date === root.selectedDate)
                root.refresh();
        }
    }

    pageSubtitle: {
        const parts = [];
        if (!VitalsService.linked)
            parts.push(Translation.tr("Phone away"));
        else if (VitalsService.syncing)
            parts.push(Translation.tr("Syncing…"));
        else if (VitalsService.lastSync > 0)
            parts.push(Translation.tr("Synced %1").arg(VitalsFormat.ago(VitalsService.lastSync, root.now)));
        const last = root.nights[0];
        if (last)
            parts.push(Translation.tr("sleep as of %1").arg(VitalsFormat.asOf(last.end, last.date, root.now)));
        return parts.join(" · ");
    }

    // Nothing to create or start here: a night opens from the ladder or the chart.
    fab: null

    // ── Navigation ──────────────────────────────────────────────────────
    /// `delta` +1 = an older night, −1 = a newer one.
    function step(delta: int): bool {
        const i = root.selectedIndex + delta;
        if (i < 0 || i >= root.nights.length)
            return false;
        root.choose(root.nights[i].date);
        return true;
    }

    /// Picks a night; an open night sheet follows it.
    function choose(date: string): void {
        root.selectedDate = date;
        if (root.panels?.isShowing(nightSheet))
            root.panels.current.date = date;
        const i = root.ladder.findIndex(r => r.key === date);
        if (i >= 0)
            ladderView.positionViewAtIndex(i, ListView.Contain);
    }

    function openNight(date: string): void {
        root.selectedDate = date;
        if (root.panels?.isShowing(nightSheet))
            root.panels.current.date = date;
        else
            root.panels?.show(nightSheet, { date: date });
    }

    function handleKey(key: int, modifiers: int): bool {
        if (key === Qt.Key_Left)
            return root.step(1);
        if (key === Qt.Key_Right)
            return root.step(-1);
        if ((key === Qt.Key_Return || key === Qt.Key_Enter) && root.selectedDate !== "") {
            root.openNight(root.selectedDate);
            return true;
        }
        return false;
    }

    // ── Helpers ─────────────────────────────────────────────────────────
    /// "7h 32" for a night's length in minutes.
    function hoursMinutes(min: real): string {
        const m = Math.round(min);
        return Translation.tr("%1h %2").arg(Math.floor(m / 60)).arg(String(m % 60).padStart(2, "0"));
    }

    /// Minutes and share per stage, deepest first; "asleep" (no stage known) last.
    function stageTotals(stages): var {
        const sum = {};
        let total = 0;
        for (const s of (Array.isArray(stages) ? stages : [])) {
            sum[s[2]] = (sum[s[2]] ?? 0) + s[1];
            total += s[1];
        }
        return ["deep", "light", "rem", "awake", "asleep"].filter(k => sum[k] > 0)
            .map(k => ({ stage: k, min: sum[k], share: sum[k] / total }));
    }

    readonly property var stageNames: ({
        deep: Translation.tr("Deep"),
        light: Translation.tr("Light"),
        rem: Translation.tr("REM"),
        awake: Translation.tr("Awake"),
        asleep: Translation.tr("Asleep")
    })

    /// The content half of each stage's colour pair (VitalsStyle.colStage).
    function colOnStage(stage: string): color {
        switch (stage) {
        case "deep": return Appearance.m3colors.darkmode ? ClockStyle.colOnPrimaryContainer : Appearance.m3colors.m3onPrimaryFixed;
        case "light": return ClockStyle.colOnPrimary;
        case "rem": return ClockStyle.colOnTertiary;
        case "awake": return Appearance.m3colors.m3surface; // outline has no on-pair; surface is what it is drawn against
        default: return ClockStyle.colOnSecondaryContainer;
        }
    }

    /// Where a time of day sits on the ladder's 20:00 → 12:00 axis (0–1), for the night
    /// that ends on `date`.
    function axisAt(ms: real, date: string): real {
        const from = new Date(Number(date.slice(0, 4)), Number(date.slice(5, 7)) - 1, Number(date.slice(8, 10)), -4).getTime();
        return Math.max(0, Math.min(1, (ms - from) / (16 * 3600000)));
    }

    /// "23:00" → the same place on the axis, for the goal window.
    function axisAtClock(hhmm: string): real {
        const m = Number(hhmm.slice(0, 2)) * 60 + Number(hhmm.slice(3, 5));
        return Math.max(0, Math.min(1, ((m - 20 * 60 + 1440) % 1440) / (16 * 60)));
    }

    readonly property real goalFrom: root.goal?.bed ? root.axisAtClock(root.goal.bed) : -1
    readonly property real goalTo: root.goal?.wake ? root.axisAtClock(root.goal.wake) : -1

    // Ladder columns: day | track | length + score.
    readonly property real dayColumn: 62
    readonly property real valueColumn: 104

    // ── Page ────────────────────────────────────────────────────────────
    ClockEmptyState {
        anchors.centerIn: parent
        visible: root.nights.length === 0
        symbol: "bedtime"
        title: Translation.tr("No nights yet")
        subtitle: Translation.tr("Nights appear here once the phone has synced a sleep session.")
    }

    Loader {
        id: sidePane
        active: root.wide && root.nights.length > 0
        visible: active
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: ClockStyle.gapTiny
        width: Math.floor((root.width - root.gap - ClockStyle.gapTiny * 2) * 0.56)
        sourceComponent: nightPaneComponent
    }

    Rectangle {
        id: ladderPane
        visible: root.nights.length > 0
        anchors.fill: parent
        anchors.margins: ClockStyle.gapTiny
        anchors.leftMargin: root.wide ? sidePane.width + root.gap + ClockStyle.gapTiny : ClockStyle.gapTiny
        radius: ClockStyle.radiusCard
        color: root.wide ? ClockStyle.colPane : "transparent"
        clip: true

        StyledListView {
            id: ladderView
            spacing: 0
            animateAppearance: false
            animatePopulate: false
            anchors.fill: parent
            anchors.margins: root.wide ? ClockStyle.gapSmall : 0
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            headerPositioning: root.wide ? ListView.OverlayHeader : ListView.InlineHeader
            bottomMargin: root.wide ? 0 : ClockStyle.gapLarge
            reuseItems: true

            model: ScriptModel {
                values: root.ladder
                objectProp: "key"
            }

            // A fixed height: a header that grows after the first layout is left above the view.
            header: Rectangle {
                width: ladderView.width
                height: (root.wide ? 0 : root.stackedPaneHeight + ClockStyle.gap) + 74
                z: 2
                color: root.wide ? ClockStyle.colPane : ClockStyle.colBackground

                ColumnLayout {
                    anchors.fill: parent
                    spacing: ClockStyle.gapSmall

                    Loader {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.stackedPaneHeight
                        Layout.bottomMargin: ClockStyle.gap
                        active: !root.wide
                        visible: active
                        sourceComponent: nightPaneComponent
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: ClockStyle.gapSmall
                        Layout.rightMargin: ClockStyle.gapSmall
                        Layout.topMargin: ClockStyle.gapSmall
                        spacing: ClockStyle.gapSmall

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Every night")
                            font.family: ClockStyle.fontTitle
                            font.variableAxes: ClockStyle.axesTitle
                            font.pixelSize: ClockStyle.textLarge
                            color: ClockStyle.colOnSurface
                        }

                        Rectangle {
                            visible: root.goalFrom >= 0
                            implicitWidth: 14
                            implicitHeight: 10
                            radius: 3
                            color: ColorUtils.applyAlpha(ClockStyle.colPrimary, 0.16)
                        }

                        StyledText {
                            visible: root.goalFrom >= 0
                            text: Translation.tr("Goal %1 → %2").arg(root.goal?.bed ?? "").arg(root.goal?.wake ?? "")
                            font.pixelSize: ClockStyle.textSmall
                            color: ClockStyle.colOnSurfaceVariant
                        }
                    }

                    // The axis: 20:00 → 12:00 over the bars' track.
                    Item {
                        id: axis
                        Layout.fillWidth: true
                        Layout.preferredHeight: 20
                        readonly property real trackX: root.dayColumn + ClockStyle.gapSmall * 2
                        readonly property real trackWidth: width - trackX - root.valueColumn - ClockStyle.gapSmall * 2
                        readonly property int every: axis.trackWidth >= 420 ? 2 : 4

                        Repeater {
                            model: 9

                            StyledText {
                                required property int index
                                readonly property int hour: (20 + index * 2) % 24
                                visible: index % (axis.every / 2) === 0
                                x: Math.round(axis.trackX + index / 8 * axis.trackWidth - width / 2)
                                text: String(hour).padStart(2, "0") + ":00"
                                font.pixelSize: ClockStyle.textSmall
                                color: ClockStyle.colOnSurfaceVariant
                                opacity: 0.8
                            }
                        }
                    }
                }
            }

            delegate: Item {
                id: row
                required property var modelData
                readonly property bool heading: modelData.heading
                width: ladderView.width
                height: row.heading ? 40 : 34

                StyledText {
                    visible: row.heading
                    anchors.left: parent.left
                    anchors.leftMargin: ClockStyle.gapSmall
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 6
                    text: {
                        const d = row.modelData.date;
                        const when = new Date(Number(d.slice(0, 4)), Number(d.slice(5, 7)) - 1, 1);
                        return Qt.locale().toString(when, d.slice(0, 4) === root.today.slice(0, 4) ? "MMMM" : "MMMM yyyy");
                    }
                    font.pixelSize: ClockStyle.textNormal
                    font.weight: Font.DemiBold
                    color: ClockStyle.colOnSurfaceVariant
                }

                RippleButton {
                    id: nightButton
                    visible: !row.heading
                    anchors.fill: parent
                    buttonRadius: ClockStyle.radiusSmall
                    toggled: !row.heading && row.modelData.date === root.selectedDate
                    colBackground: "transparent"
                    colBackgroundHover: ColorUtils.applyAlpha(ClockStyle.colOnSurface, 0.08)
                    colRipple: ColorUtils.applyAlpha(ClockStyle.colOnSurface, 0.16)
                    colBackgroundToggled: ClockStyle.colSecondaryContainer
                    colBackgroundToggledHover: ClockStyle.colSecondaryContainerHover
                    colRippleToggled: ClockStyle.colSecondaryContainerActive
                    onClicked: root.openNight(row.modelData.date)

                    readonly property color colText: nightButton.toggled ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface
                    readonly property color colTextVariant: nightButton.toggled ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurfaceVariant

                    contentItem: Item {
                        opacity: VitalsStyle.emphasis(row.modelData.date ?? "", root.today)

                        StyledText {
                            x: ClockStyle.gapSmall
                            width: root.dayColumn
                            anchors.verticalCenter: parent.verticalCenter
                            text: {
                                const d = row.modelData.date ?? "";
                                if (d === "")
                                    return "";
                                return Qt.locale().toString(new Date(Number(d.slice(0, 4)), Number(d.slice(5, 7)) - 1, Number(d.slice(8, 10))), "ddd d");
                            }
                            elide: Text.ElideRight
                            font.pixelSize: ClockStyle.textSmall
                            font.weight: Font.DemiBold
                            color: nightButton.colTextVariant
                        }

                        Item {
                            id: track
                            x: root.dayColumn + ClockStyle.gapSmall * 2
                            width: parent.width - x - root.valueColumn - ClockStyle.gapSmall * 2
                            height: parent.height

                            // The goal window, one band down the whole ladder.
                            Rectangle {
                                visible: root.goalFrom >= 0 && root.goalTo > root.goalFrom
                                x: Math.round(root.goalFrom * track.width)
                                width: Math.round((root.goalTo - root.goalFrom) * track.width)
                                height: parent.height
                                color: ColorUtils.applyAlpha(ClockStyle.colPrimary, 0.1)
                            }

                            Rectangle {
                                readonly property real from: row.heading ? 0 : root.axisAt(row.modelData.start, row.modelData.date)
                                readonly property real to: row.heading ? 0 : root.axisAt(row.modelData.end, row.modelData.date)
                                x: Math.round(from * track.width)
                                width: Math.max(4, Math.round((to - from) * track.width))
                                height: 14
                                anchors.verticalCenter: parent.verticalCenter
                                radius: ClockStyle.pill(height)
                                color: ClockStyle.colPrimary
                            }
                        }

                        StyledText {
                            anchors.right: scorePill.left
                            anchors.rightMargin: ClockStyle.gapSmall
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.heading ? "" : root.hoursMinutes(row.modelData.min)
                            font.family: ClockStyle.fontMain
                            font.variableAxes: ClockStyle.axesDigits
                            font.pixelSize: ClockStyle.textLarge
                            color: nightButton.colText
                        }

                        Rectangle {
                            id: scorePill
                            anchors.right: parent.right
                            anchors.rightMargin: ClockStyle.gapSmall
                            anchors.verticalCenter: parent.verticalCenter
                            width: 30
                            height: 22
                            radius: ClockStyle.pill(height)
                            opacity: !row.heading && row.modelData.score !== null ? 1 : 0
                            color: ClockStyle.colTertiaryContainer

                            StyledText {
                                anchors.centerIn: parent
                                text: String(row.modelData.score ?? "")
                                font.pixelSize: ClockStyle.textSmall
                                font.weight: Font.Bold
                                color: ClockStyle.colOnTertiaryContainer
                            }
                        }
                    }
                }
            }
        }
    }

    // ── The chosen night ────────────────────────────────────────────────
    Component {
        id: nightPaneComponent

        Rectangle {
            id: pane
            radius: ClockStyle.radiusCard
            color: ClockStyle.colPane

            readonly property var n: root.night
            readonly property string date: root.selectedDate
            readonly property var totals: root.stageTotals(pane.n?.stages)
            readonly property bool isLast: root.selectedIndex === 0 && pane.date === root.today

            Component.onCompleted: root.grown = true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: VitalsStyle.tilePadding
                anchors.topMargin: VitalsStyle.tilePadding - 6
                spacing: ClockStyle.gap
                opacity: VitalsStyle.emphasis(pane.date, root.today)

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall

                    MaterialSymbol {
                        text: "bedtime"
                        iconSize: ClockStyle.iconSmall + 2
                        fill: 1
                        color: ClockStyle.colOnSurface
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: pane.isLast ? Translation.tr("Last night") : VitalsFormat.dayLabel(pane.date, root.now)
                        elide: Text.ElideRight
                        font.pixelSize: ClockStyle.textNormal
                        font.weight: Font.DemiBold
                        color: ClockStyle.colOnSurface
                    }

                    ClockCardAction {
                        symbol: "chevron_left"
                        tip: Translation.tr("Older night (←)")
                        enabled: root.selectedIndex < root.nights.length - 1
                        onClicked: root.step(1)
                    }

                    ClockCardAction {
                        symbol: "chevron_right"
                        tip: Translation.tr("Newer night (→)")
                        enabled: root.selectedIndex > 0
                        onClicked: root.step(-1)
                    }

                    ClockCardAction {
                        symbol: "info"
                        tip: Translation.tr("Night details (Enter)")
                        onClicked: root.openNight(pane.date)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapLarge

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            text: pane.n ? root.hoursMinutes(pane.n.min) : ""
                            font.family: ClockStyle.fontMain
                            font.variableAxes: ClockStyle.axesDigitsBold
                            font.pixelSize: Math.round(Math.max(44, Math.min(76, pane.width * 0.11)))
                            color: ClockStyle.colOnSurface
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: pane.n
                                ? VitalsFormat.clock(pane.n.start) + " → " + VitalsFormat.clock(pane.n.end)
                                    + (root.goal?.bed && root.goal?.wake ? " · " + Translation.tr("goal %1 → %2").arg(root.goal.bed).arg(root.goal.wake) : "")
                                : ""
                            elide: Text.ElideRight
                            font.pixelSize: ClockStyle.textNormal
                            color: ClockStyle.colOnSurfaceVariant
                        }
                    }

                    // The score fills a ring; a night without one keeps the space empty.
                    Item {
                        visible: pane.n?.score !== null && pane.n?.score !== undefined
                        implicitWidth: 84
                        implicitHeight: 84

                        ClockProgressRing {
                            anchors.fill: parent
                            value: (pane.n?.score ?? 0) / 100
                            thickness: 8
                            waves: 10
                            multisample: true
                            colIndicator: ClockStyle.colTertiary
                            colTrack: ClockStyle.colTertiaryContainer
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: -4

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: String(pane.n?.score ?? "")
                                font.family: ClockStyle.fontMain
                                font.variableAxes: ClockStyle.axesDigitsBold
                                font.pixelSize: 30
                                color: ClockStyle.colOnSurface
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: Translation.tr("Score")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.Bold
                                color: ClockStyle.colOnSurfaceVariant
                            }
                        }
                    }
                }

                VitalsHypnogram {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 150
                    entrance: !root.grown
                    stages: pane.n?.stages ?? null
                    start: pane.n?.start ?? 0
                    end: pane.n?.end ?? 0
                }

                Flow {
                    Layout.fillWidth: true
                    visible: pane.totals.length > 1
                    spacing: ClockStyle.gapLarge

                    Repeater {
                        model: ScriptModel {
                            values: pane.totals
                            objectProp: "stage"
                        }

                        RowLayout {
                            id: legendItem
                            required property var modelData
                            spacing: 6

                            Rectangle {
                                implicitWidth: 10
                                implicitHeight: 10
                                radius: 5
                                color: VitalsStyle.colStage(legendItem.modelData.stage)
                            }

                            StyledText {
                                text: root.stageNames[legendItem.modelData.stage] ?? ""
                                font.pixelSize: ClockStyle.textSmall
                                font.weight: Font.DemiBold
                                color: ClockStyle.colOnSurface
                            }

                            StyledText {
                                text: Translation.tr("%1 · %2 %").arg(VitalsTypes.duration(legendItem.modelData.min)).arg(Math.round(legendItem.modelData.share * 100))
                                font.pixelSize: ClockStyle.textSmall
                                color: ClockStyle.colOnSurfaceVariant
                            }
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: pane.n !== null && pane.totals.length <= 1
                    text: pane.n?.stages === null ? Translation.tr("Reading the stages…") : Translation.tr("No stages recorded for this night")
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colOnSurfaceVariant
                }
            }
        }
    }

    // ── A night's sheet ─────────────────────────────────────────────────
    Component {
        id: nightSheet

        ClockSheet {
            id: sheet
            property string date: ""
            property var n: null
            property var session: null
            property var skin: null

            readonly property var totals: root.stageTotals(sheet.n?.stages)
            readonly property var sourceNames: ({ samsung: Translation.tr("Samsung Health"), healthConnect: Translation.tr("Health Connect") })

            title: sheet.date === root.today ? Translation.tr("Last night") : VitalsFormat.dayLabel(sheet.date, root.now)
            subtitle: sheet.n ? VitalsFormat.clock(sheet.n.start) + " → " + VitalsFormat.clock(sheet.n.end)
                + (sheet.n.source ? " · " + (sheet.sourceNames[sheet.n.source] ?? sheet.n.source) : "") : ""

            function refresh(): void {
                sheet.n = VitalsService.sleepFor(sheet.date);
                const day = VitalsService.day(sheet.date);
                sheet.session = day && sheet.n ? ((day.sessions?.sleep ?? []).find(s => s.start === sheet.n.start) ?? null) : null;
                sheet.skin = sheet.skinOf(day);
            }

            /// The night's skin temperature: the samples inside the session when the day file
            /// has them, else the day's mean from the index.
            function skinOf(day): var {
                const key = VitalsService.present.skinTempC ? "skinTempC" : VitalsService.present.skinTempDeltaC ? "skinTempDeltaC" : "";
                if (key === "" || !sheet.n)
                    return null;
                const smp = day?.samples?.[key];
                if (smp?.bins) {
                    const midnight = new Date(Number(sheet.date.slice(0, 4)), Number(sheet.date.slice(5, 7)) - 1, Number(sheet.date.slice(8, 10))).getTime();
                    const from = (sheet.n.start - midnight) / 60000, to = (sheet.n.end - midnight) / 60000;
                    const inside = smp.bins.filter(b => b[0] >= from && b[0] <= to).map(b => b[1]);
                    if (inside.length > 0)
                        return { key: key, avg: inside.reduce((a, b) => a + b, 0) / inside.length, min: Math.min(...inside), max: Math.max(...inside) };
                }
                const s = VitalsService.summary(sheet.date)?.s?.[key];
                return s ? { key: key, avg: s[1], min: s[0], max: s[2] } : null;
            }

            Component.onCompleted: sheet.refresh()
            onDateChanged: sheet.refresh()

            Connections {
                target: VitalsService
                function onDayLoaded(date) {
                    if (date === sheet.date)
                        sheet.refresh();
                }
            }

            // On the sheet itself, as on the page's pane.
            VitalsHypnogram {
                Layout.fillWidth: true
                Layout.preferredHeight: 170
                stages: sheet.n?.stages ?? null
                start: sheet.n?.start ?? 0
                end: sheet.n?.end ?? 0
            }

            // Minutes per stage, each in its own colour pair.
            GridLayout {
                Layout.fillWidth: true
                visible: sheet.totals.length > 1
                columns: 2
                columnSpacing: ClockStyle.gapSmall
                rowSpacing: ClockStyle.gapSmall

                Repeater {
                    model: ScriptModel {
                        values: sheet.totals
                        objectProp: "stage"
                    }

                    Rectangle {
                        id: stageTile
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        implicitHeight: 70
                        radius: ClockStyle.radiusSmall
                        color: VitalsStyle.colStage(stageTile.modelData.stage)

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 0

                            RowLayout {
                                Layout.fillWidth: true

                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.stageNames[stageTile.modelData.stage] ?? ""
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.Bold
                                    color: root.colOnStage(stageTile.modelData.stage)
                                }

                                StyledText {
                                    text: Translation.tr("%1 %").arg(Math.round(stageTile.modelData.share * 100))
                                    font.pixelSize: ClockStyle.textSmall
                                    font.weight: Font.DemiBold
                                    color: root.colOnStage(stageTile.modelData.stage)
                                }
                            }

                            Item {
                                Layout.fillHeight: true
                            }

                            StyledText {
                                text: root.hoursMinutes(stageTile.modelData.min)
                                font.family: ClockStyle.fontMain
                                font.variableAxes: ClockStyle.axesDigitsBold
                                font.pixelSize: 26
                                color: root.colOnStage(stageTile.modelData.stage)
                            }
                        }
                    }
                }
            }

            VitalsFactRow {
                symbol: "schedule"
                shapeKind: MaterialShape.Shape.Cookie9Sided
                caption: Translation.tr("Time in bed")
                value: {
                    if (!sheet.n)
                        return "–";
                    const awake = sheet.totals.find(t => t.stage === "awake")?.min ?? 0;
                    const bed = VitalsTypes.duration(sheet.n.min);
                    return awake > 0 ? Translation.tr("%1 · %2 asleep").arg(bed).arg(VitalsTypes.duration(sheet.n.min - awake)) : bed;
                }
            }

            VitalsFactRow {
                visible: sheet.n?.score !== null && sheet.n?.score !== undefined
                symbol: "star"
                shapeKind: MaterialShape.Shape.Sunny
                caption: Translation.tr("Sleep score")
                value: Translation.tr("%1 of 100").arg(sheet.n?.score ?? 0)
            }

            VitalsFactRow {
                visible: typeof sheet.session?.efficiency === "number"
                symbol: "percent"
                shapeKind: MaterialShape.Shape.Clover4Leaf
                caption: Translation.tr("Efficiency")
                value: Translation.tr("%1 % of the time in bed").arg(Math.round(sheet.session?.efficiency ?? 0))
            }

            VitalsFactRow {
                visible: sheet.skin !== null
                symbol: "thermostat"
                shapeKind: MaterialShape.Shape.SoftBurst
                caption: Translation.tr("Skin temperature")
                value: sheet.skin
                    ? Translation.tr("%1 (%2 to %3)").arg(VitalsTypes.format(sheet.skin.key, sheet.skin.avg))
                        .arg(VitalsTypes.format(sheet.skin.key, sheet.skin.min)).arg(VitalsTypes.format(sheet.skin.key, sheet.skin.max))
                    : ""
            }

            StyledText {
                Layout.fillWidth: true
                visible: sheet.n === null
                text: Translation.tr("No sleep session ends on this day.")
                wrapMode: Text.WordWrap
                font.pixelSize: ClockStyle.textSmall
                color: ClockStyle.colOnSurfaceVariant
            }
        }
    }
}
