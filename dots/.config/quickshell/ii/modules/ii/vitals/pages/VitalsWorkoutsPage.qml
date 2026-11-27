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
 * Workouts: every session in one column, newest first, under a heading per week or
 * month with that period's count and time. A session opens its sheet: the heart-rate
 * curve during it, speed when the phone recorded it, time in each age-based heart-rate
 * zone, and the route as a line when one was sent. ←/→ jump between periods.
 *
 * The list is built from the index (which days have sessions, how many); a day's
 * sessions are read from its day file only when that day scrolls into view, and kept
 * here so scrolling back does not ask the service again.
 */
VitalsPage {
    id: root

    // ── Layout ──────────────────────────────────────────────────────────
    /// Stats in columns beside the title; below it, one line under the title.
    readonly property bool wideRows: root.layoutWidth >= 760
    readonly property real cardHeight: root.wideRows ? 84 : 96
    readonly property real cardGap: ClockStyle.gapSmall

    // ── Data ────────────────────────────────────────────────────────────
    readonly property string today: VitalsFormat.dateOf(root.now)
    property string grouping: "week"

    /// Days with sessions, newest first, from the index.
    readonly property var days: {
        VitalsService.dataVersion;
        const out = [];
        const dates = VitalsService.dates;
        for (let i = dates.length - 1; i >= 0; i--) {
            const s = VitalsService.summary(dates[i]);
            if ((s?.n?.exercise ?? 0) > 0)
                out.push({ date: dates[i], n: s.n.exercise, exMin: s.exMin ?? 0 });
        }
        return out;
    }
    readonly property int total: root.days.reduce((a, d) => a + d.n, 0)

    function dateOfKey(date: string): var {
        return new Date(Number(date.slice(0, 4)), Number(date.slice(5, 7)) - 1, Number(date.slice(8, 10)));
    }

    /// The first day of the week or month `date` is in.
    function periodOf(date: string): string {
        if (root.grouping === "month")
            return date.slice(0, 7) + "-01";
        const d = root.dateOfKey(date);
        return VitalsFormat.addDays(date, -((d.getDay() - Qt.locale().firstDayOfWeek + 7) % 7));
    }

    function periodLabel(first: string): string {
        const year = first.slice(0, 4) === root.today.slice(0, 4);
        if (root.grouping === "month")
            return Qt.locale().toString(root.dateOfKey(first), year ? "MMMM" : "MMMM yyyy");
        const thisWeek = root.periodOf(root.today);
        if (first === thisWeek)
            return Translation.tr("This week");
        if (first === VitalsFormat.addDays(thisWeek, -7))
            return Translation.tr("Last week");
        const last = VitalsFormat.addDays(first, 6);
        const a = root.dateOfKey(first), b = root.dateOfKey(last);
        const sameMonth = first.slice(0, 7) === last.slice(0, 7);
        return Translation.tr("%1 – %2").arg(Qt.locale().toString(a, sameMonth ? "d" : "d MMM"))
            .arg(Qt.locale().toString(b, last.slice(0, 4) === root.today.slice(0, 4) ? "d MMM" : "d MMM yyyy"));
    }

    /// The list: a heading per period, then its days.
    readonly property var rows: {
        const out = [];
        let i = 0;
        while (i < root.days.length) {
            const first = root.periodOf(root.days[i].date);
            const members = [];
            while (i < root.days.length && root.periodOf(root.days[i].date) === first)
                members.push(root.days[i++]);
            const count = members.reduce((a, d) => a + d.n, 0);
            const minutes = members.reduce((a, d) => a + d.exMin, 0);
            out.push({
                key: root.grouping + first,
                heading: true,
                date: first,
                label: root.periodLabel(first),
                summary: (count === 1 ? Translation.tr("1 workout") : Translation.tr("%1 workouts").arg(count)) + " · " + VitalsTypes.duration(minutes)
            });
            for (const d of members)
                out.push({ key: d.date, heading: false, date: d.date, n: d.n });
        }
        return out;
    }

    // Sessions per date, newest first, read as their days scroll into view.
    property var sessions: ({})
    property int sessionsVersion: 0
    property var waiting: ({})

    function need(date: string): void {
        if (root.sessions[date] !== undefined)
            return;
        const day = VitalsService.day(date);
        if (day)
            root.keep(date, day);
        else
            root.waiting[date] = true;
    }

    function keep(date: string, day: var): void {
        root.sessions[date] = (day.sessions?.exercise ?? []).slice().sort((a, b) => b.start - a.start);
        root.sessionsVersion++;
    }

    Connections {
        target: VitalsService
        function onDayLoaded(date) {
            if (!root.waiting[date])
                return;
            delete root.waiting[date];
            const day = VitalsService.day(date);
            if (day)
                root.keep(date, day);
        }
        // A sync can change any day; the visible ones read theirs again.
        function onDataVersionChanged() {
            root.sessions = {};
            root.waiting = {};
            root.sessionsVersion++;
        }
    }

    readonly property var newest: {
        root.sessionsVersion;
        const d = root.days[0];
        return d ? (root.sessions[d.date]?.[0] ?? null) : null;
    }

    pageSubtitle: {
        const parts = [];
        if (!VitalsService.linked)
            parts.push(Translation.tr("Phone away"));
        else if (VitalsService.syncing)
            parts.push(Translation.tr("Syncing…"));
        else if (VitalsService.lastSync > 0)
            parts.push(Translation.tr("Synced %1").arg(VitalsFormat.ago(VitalsService.lastSync, root.now)));
        if (root.days.length > 0)
            parts.push(Translation.tr("latest workout %1").arg(VitalsFormat.asOf(root.newest?.start ?? 0, root.days[0].date, root.now)));
        return parts.join(" · ");
    }

    // Workouts are recorded on the watch or phone; there is nothing to start here.
    fab: null

    // ── Navigation ──────────────────────────────────────────────────────
    /// Scrolls to the next older (+1) or newer (−1) period's heading.
    function jump(delta: int): bool {
        const top = Math.max(0, list.indexAt(10, list.contentY + 1));
        let current = top;
        while (current > 0 && !root.rows[current].heading)
            current--;
        let i = current + delta;
        while (i >= 0 && i < root.rows.length && !root.rows[i].heading)
            i += delta;
        if (i < 0 || i >= root.rows.length)
            return false;
        list.positionViewAtIndex(i, ListView.Beginning);
        return true;
    }

    function handleKey(key: int, modifiers: int): bool {
        if (key === Qt.Key_Left)
            return root.jump(1);
        if (key === Qt.Key_Right)
            return root.jump(-1);
        return false;
    }

    function openSession(date: string, session: var): void {
        root.panels?.show(sessionSheet, { date: date, sid: session.id, session: session });
    }

    function isOpen(sid: string): bool {
        return root.panels?.isShowing(sessionSheet) === true && root.panels.current?.sid === sid;
    }

    /// The card's four columns, always in the same slots so the cards line up; a column a
    /// session lacks stays empty. `short` is the compact line's wording.
    function statsOf(s: var): var {
        const has = v => typeof v === "number";
        const hr = !has(s.hrAvg) ? "" : has(s.hrMax)
            ? Translation.tr("%1 avg · %2 max").arg(Math.round(s.hrAvg)).arg(Math.round(s.hrMax))
            : VitalsTypes.format("heartRate", s.hrAvg);
        const time = VitalsTypes.duration((s.end - s.start) / 60000);
        const dist = has(s.distanceM) ? VitalsTypes.format("distanceM", s.distanceM) : "";
        const kcal = has(s.kcal) ? VitalsTypes.format("activeKcal", s.kcal) : "";
        return [
            { key: "time", caption: Translation.tr("Duration"), value: time, short: time },
            { key: "dist", caption: Translation.tr("Distance"), value: dist, short: dist },
            { key: "kcal", caption: Translation.tr("Calories"), value: kcal, short: kcal },
            { key: "hr", caption: Translation.tr("Heart rate"), value: hr, short: has(s.hrAvg) ? Translation.tr("avg %1").arg(VitalsTypes.format("heartRate", s.hrAvg)) : "" }
        ];
    }

    function titleOf(s: var): string {
        return s.title ?? VitalsTypes.exerciseLabel(s.type);
    }

    // ── Page ────────────────────────────────────────────────────────────
    ClockEmptyState {
        anchors.centerIn: parent
        visible: root.days.length === 0
        symbol: "exercise"
        title: Translation.tr("No workouts yet")
        subtitle: Translation.tr("Workouts appear here once the watch or phone has recorded one.")
    }

    StyledListView {
        id: list
        spacing: 0
        animateAppearance: false
        animatePopulate: false
        anchors.fill: parent
        anchors.margins: ClockStyle.gapTiny
        visible: root.days.length > 0
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        bottomMargin: ClockStyle.fabClearance / 2
        reuseItems: true

        model: ScriptModel {
            values: root.rows
            objectProp: "key"
        }

        header: Item {
            width: list.width
            height: 52

            RowLayout {
                anchors.fill: parent
                anchors.bottomMargin: ClockStyle.gapSmall
                spacing: ClockStyle.gapSmall

                ClockFormChip {
                    label: Translation.tr("By week")
                    selected: root.grouping === "week"
                    onTriggered: root.grouping = "week"
                }

                ClockFormChip {
                    label: Translation.tr("By month")
                    selected: root.grouping === "month"
                    onTriggered: root.grouping = "month"
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    text: root.days.length > 0
                        ? Translation.tr("%1 workouts since %2").arg(root.total).arg(VitalsFormat.dayLabel(root.days[root.days.length - 1].date, root.now))
                        : ""
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colOnSurfaceVariant
                }
            }
        }

        delegate: Item {
            id: row
            required property var modelData
            readonly property bool heading: modelData.heading
            readonly property var daySessions: {
                root.sessionsVersion;
                return row.heading ? null : (root.sessions[row.modelData.date] ?? null);
            }
            readonly property real emphasis: VitalsStyle.emphasis(row.modelData.date, root.today)

            width: list.width
            height: row.heading ? 64 : row.modelData.n * (root.cardHeight + root.cardGap)

            // Reused delegates get a new day: ask for it whenever the date changes.
            onModelDataChanged: if (!row.heading) root.need(row.modelData.date)
            Component.onCompleted: if (!row.heading) root.need(row.modelData.date)

            ColumnLayout {
                visible: row.heading
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: ClockStyle.gapTiny
                anchors.bottomMargin: ClockStyle.gapSmall
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: row.modelData.label ?? ""
                    elide: Text.ElideRight
                    font.family: ClockStyle.fontTitle
                    font.variableAxes: ClockStyle.axesTitle
                    font.pixelSize: ClockStyle.textLarge
                    color: ClockStyle.colOnSurface
                    opacity: row.emphasis
                }

                StyledText {
                    Layout.fillWidth: true
                    text: row.modelData.summary ?? ""
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colOnSurfaceVariant
                    opacity: row.emphasis
                }
            }

            Column {
                visible: !row.heading
                width: parent.width
                spacing: root.cardGap

                Repeater {
                    model: ScriptModel {
                        values: row.daySessions ?? []
                        objectProp: "id"
                    }

                    RippleButton {
                        id: card
                        required property var modelData
                        readonly property var stats: root.statsOf(card.modelData)
                        readonly property bool open: {
                            root.panels?.open;
                            root.panels?.current;
                            return root.isOpen(card.modelData.id);
                        }

                        width: row.width
                        height: root.cardHeight
                        buttonRadius: ClockStyle.radiusLarge
                        toggled: card.open
                        colBackground: ClockStyle.colPane
                        colBackgroundHover: ClockStyle.colIdleCardHover
                        colRipple: Appearance.colors.colLayer1Active
                        colBackgroundToggled: ClockStyle.colSecondaryContainer
                        colBackgroundToggledHover: ClockStyle.colSecondaryContainerHover
                        colRippleToggled: ClockStyle.colSecondaryContainerActive
                        onClicked: root.openSession(row.modelData.date, card.modelData)

                        readonly property color colText: card.open ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface
                        readonly property color colTextVariant: card.open ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurfaceVariant

                        contentItem: RowLayout {
                            spacing: ClockStyle.gapLarge
                            opacity: row.emphasis

                            MaterialShapeWrappedMaterialSymbol {
                                Layout.leftMargin: ClockStyle.gap
                                text: VitalsTypes.exerciseIcon(card.modelData.type)
                                iconSize: ClockStyle.iconNormal
                                padding: 11
                                fill: 1
                                shape: card.hovered || card.open ? MaterialShape.Shape.Cookie12Sided : MaterialShape.Shape.Cookie9Sided
                                color: card.open ? ClockStyle.colTertiary : ClockStyle.colSecondaryContainer
                                colSymbol: card.open ? ClockStyle.colOnTertiary : ClockStyle.colOnSecondaryContainer
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 200
                                spacing: 0

                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.titleOf(card.modelData)
                                    elide: Text.ElideRight
                                    font.family: ClockStyle.fontTitle
                                    font.variableAxes: ClockStyle.axesTitle
                                    font.pixelSize: ClockStyle.textLarge
                                    color: card.colText
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: VitalsFormat.dayLabel(row.modelData.date, root.now) + " · "
                                        + VitalsFormat.clock(card.modelData.start) + "–" + VitalsFormat.clock(card.modelData.end)
                                    elide: Text.ElideRight
                                    font.pixelSize: ClockStyle.textSmall
                                    color: card.colTextVariant
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 4
                                    visible: !root.wideRows
                                    text: card.stats.map(s => s.short).filter(v => v.length > 0).join(" · ")
                                    elide: Text.ElideRight
                                    font.pixelSize: ClockStyle.textNormal
                                    font.weight: Font.DemiBold
                                    color: card.colText
                                }
                            }

                            Repeater {
                                model: ScriptModel {
                                    values: root.wideRows ? card.stats : []
                                    objectProp: "key"
                                }

                                ColumnLayout {
                                    id: stat
                                    required property var modelData
                                    required property int index
                                    Layout.preferredWidth: stat.modelData.key === "hr" ? 132 : 92
                                    Layout.rightMargin: stat.index === card.stats.length - 1 ? ClockStyle.gapLarge : 0
                                    spacing: 0

                                    StyledText {
                                        visible: stat.modelData.value.length > 0
                                        text: stat.modelData.caption
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.Bold
                                        color: card.colTextVariant
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: stat.modelData.value
                                        elide: Text.ElideRight
                                        font.family: stat.modelData.key === "time" ? ClockStyle.fontMain : Appearance.font.family.main
                                        font.variableAxes: stat.modelData.key === "time" ? ClockStyle.axesDigitsBold : ({})
                                        font.pixelSize: stat.modelData.key === "time" ? ClockStyle.textLarge + 2 : ClockStyle.textNormal
                                        font.weight: Font.Bold
                                        color: card.colText
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── A session's sheet ───────────────────────────────────────────────
    Component {
        id: sessionSheet

        ClockSheet {
            id: sheet
            property string date: ""
            property string sid: ""
            property var session: null

            property var hr: []
            property var speed: []
            property var zoneMinutes: []
            property var routePoints: null

            readonly property var zones: VitalsService.hrZones()
            readonly property bool hasRoute: sheet.session?.route === true

            title: sheet.session ? root.titleOf(sheet.session) : Translation.tr("Workout")
            subtitle: sheet.session
                ? VitalsFormat.dayLabel(sheet.date, root.now) + " · " + VitalsFormat.clock(sheet.session.start) + "–" + VitalsFormat.clock(sheet.session.end)
                : ""

            /// One value per bin inside the session (null where the bin is empty).
            function slice(day, key: string): var {
                const smp = day?.samples?.[key];
                if (!smp?.bins || !sheet.session)
                    return [];
                const bm = Math.max(1, smp.binMin ?? 1);
                const midnight = root.dateOfKey(sheet.date).getTime();
                const from = (sheet.session.start - midnight) / 60000, to = (sheet.session.end - midnight) / 60000;
                const out = new Array(Math.max(1, Math.ceil((to - from) / bm))).fill(null);
                for (const b of smp.bins) {
                    if (b[0] + bm > from && b[0] < to)
                        out[Math.min(out.length - 1, Math.max(0, Math.floor((b[0] - from) / bm)))] = b[1];
                }
                return out.some(v => v !== null) ? out : [];
            }

            function refresh(): void {
                const day = VitalsService.day(sheet.date);
                if (day && sheet.session)
                    sheet.session = (day.sessions?.exercise ?? []).find(s => s.id === sheet.sid) ?? sheet.session;
                sheet.hr = sheet.slice(day, "heartRate");
                sheet.speed = sheet.slice(day, "speedMps");
                const bm = Math.max(1, day?.samples?.heartRate?.binMin ?? 1);
                sheet.zoneMinutes = sheet.zones.map(z => sheet.hr.filter(v => v !== null && v >= z.from && (v < z.to || z.zone === 5)).length * bm);
                if (sheet.hasRoute)
                    sheet.routePoints = VitalsService.route(sheet.sid);
            }

            Component.onCompleted: sheet.refresh()
            onSidChanged: sheet.refresh()

            Connections {
                target: VitalsService
                function onDayLoaded(date) {
                    if (date === sheet.date)
                        sheet.refresh();
                }
                function onRouteLoaded(id) {
                    if (id === sheet.sid)
                        sheet.routePoints = VitalsService.route(id);
                }
            }

            readonly property var facts: {
                const s = sheet.session;
                if (!s)
                    return [];
                const out = [{ key: "time", symbol: "timer", shape: MaterialShape.Shape.Cookie9Sided, caption: Translation.tr("Duration"), value: VitalsTypes.duration((s.end - s.start) / 60000) }];
                if (typeof s.distanceM === "number")
                    out.push({ key: "dist", symbol: "straighten", shape: MaterialShape.Shape.Pill, caption: Translation.tr("Distance"), value: VitalsTypes.format("distanceM", s.distanceM) });
                if (typeof s.kcal === "number")
                    out.push({ key: "kcal", symbol: "local_fire_department", shape: MaterialShape.Shape.SoftBurst, caption: Translation.tr("Calories"), value: VitalsTypes.format("activeKcal", s.kcal) });
                if (typeof s.hrAvg === "number")
                    out.push({ key: "hrAvg", symbol: "favorite", shape: MaterialShape.Shape.Heart, caption: Translation.tr("Average heart rate"), value: VitalsTypes.format("heartRate", s.hrAvg) });
                if (typeof s.hrMax === "number")
                    out.push({ key: "hrMax", symbol: "ecg_heart", shape: MaterialShape.Shape.Sunny, caption: Translation.tr("Highest heart rate"), value: VitalsTypes.format("heartRate", s.hrMax) });
                if (typeof s.speedAvgMps === "number")
                    out.push({ key: "speed", symbol: "speed", shape: MaterialShape.Shape.Clover4Leaf, caption: Translation.tr("Average speed"), value: VitalsTypes.format("speedMps", s.speedAvgMps) });
                if (typeof s.elevationM === "number")
                    out.push({ key: "elev", symbol: "landscape", shape: MaterialShape.Shape.Triangle, caption: Translation.tr("Elevation gained"), value: VitalsTypes.format("elevationM", s.elevationM) });
                if (typeof s.steps === "number")
                    out.push({ key: "steps", symbol: "footprint", shape: MaterialShape.Shape.Cookie6Sided, caption: Translation.tr("Steps"), value: VitalsTypes.format("steps", s.steps) });
                return out;
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: ClockStyle.gapSmall
                rowSpacing: ClockStyle.gapSmall

                Repeater {
                    model: ScriptModel {
                        values: sheet.facts
                        objectProp: "key"
                    }

                    VitalsFactRow {
                        required property var modelData
                        Layout.preferredWidth: 1
                        symbol: modelData.symbol
                        shapeKind: modelData.shape
                        caption: modelData.caption
                        value: modelData.value
                    }
                }
            }

            // ── Curves ──────────────────────────────────────────────
            Repeater {
                model: ScriptModel {
                    values: [
                        { key: "heartRate", caption: Translation.tr("Heart rate"), values: sheet.hr, color: ClockStyle.colPrimary },
                        { key: "speedMps", caption: Translation.tr("Speed"), values: sheet.speed, color: ClockStyle.colTertiary }
                    ].filter(c => c.values.length > 0)
                    objectProp: "key"
                }

                Rectangle {
                    id: curve
                    required property var modelData
                    readonly property var known: curve.modelData.values.filter(v => v !== null)
                    readonly property real lo: Math.min(...curve.known)
                    readonly property real hi: Math.max(...curve.known)

                    Layout.fillWidth: true
                    implicitHeight: 150
                    radius: ClockStyle.radiusLarge
                    color: ClockStyle.colField

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: ClockStyle.gap
                        spacing: ClockStyle.gapTiny

                        RowLayout {
                            Layout.fillWidth: true

                            StyledText {
                                Layout.fillWidth: true
                                text: curve.modelData.caption
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.Bold
                                color: ClockStyle.colOnSurfaceVariant
                            }

                            StyledText {
                                text: Translation.tr("%1 to %2").arg(VitalsTypes.format(curve.modelData.key, curve.lo)).arg(VitalsTypes.format(curve.modelData.key, curve.hi))
                                font.pixelSize: ClockStyle.textSmall
                                font.weight: Font.DemiBold
                                color: ClockStyle.colOnSurface
                            }
                        }

                        HealthSparkline {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            values: curve.modelData.values
                            color: curve.modelData.color
                        }

                        RowLayout {
                            Layout.fillWidth: true

                            StyledText {
                                Layout.fillWidth: true
                                text: sheet.session ? VitalsFormat.clock(sheet.session.start) : ""
                                font.pixelSize: ClockStyle.textSmall
                                color: ClockStyle.colOnSurfaceVariant
                            }

                            StyledText {
                                text: sheet.session ? VitalsFormat.clock(sheet.session.end) : ""
                                font.pixelSize: ClockStyle.textSmall
                                color: ClockStyle.colOnSurfaceVariant
                            }
                        }
                    }
                }
            }

            // ── Heart-rate zones ────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                visible: sheet.hr.length > 0
                implicitHeight: zoneColumn.implicitHeight + ClockStyle.gap * 2
                radius: ClockStyle.radiusLarge
                color: ClockStyle.colField

                ColumnLayout {
                    id: zoneColumn
                    anchors.fill: parent
                    anchors.margins: ClockStyle.gap
                    spacing: ClockStyle.gapSmall

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Time in heart-rate zones")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Bold
                        color: ClockStyle.colOnSurfaceVariant
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: sheet.zones.length === 0
                        text: Translation.tr("The phone's health profile has no birth date, so zones are unknown.")
                        wrapMode: Text.WordWrap
                        font.pixelSize: ClockStyle.textSmall
                        color: ClockStyle.colOnSurface
                    }

                    Repeater {
                        model: ScriptModel {
                            // Hardest first, as a watch lists them.
                            values: sheet.zones.slice().reverse()
                            objectProp: "zone"
                        }

                        RowLayout {
                            id: zoneRow
                            required property var modelData
                            readonly property real minutes: sheet.zoneMinutes[zoneRow.modelData.zone - 1] ?? 0
                            readonly property real most: Math.max(1, ...sheet.zoneMinutes)
                            Layout.fillWidth: true
                            spacing: ClockStyle.gapSmall

                            ColumnLayout {
                                Layout.preferredWidth: 84
                                spacing: -2

                                StyledText {
                                    text: Translation.tr("Zone %1").arg(zoneRow.modelData.zone)
                                    font.pixelSize: ClockStyle.textSmall
                                    font.weight: Font.Bold
                                    color: ClockStyle.colOnSurface
                                }

                                StyledText {
                                    text: Translation.tr("%1–%2 bpm").arg(zoneRow.modelData.from).arg(zoneRow.modelData.to)
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: ClockStyle.colOnSurfaceVariant
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                                implicitHeight: 12

                                Rectangle {
                                    width: Math.max(zoneRow.minutes > 0 ? 6 : 0, parent.width * zoneRow.minutes / zoneRow.most)
                                    height: parent.height
                                    radius: ClockStyle.pill(height)
                                    // Harder zones in fuller primary; one hue for the whole scale.
                                    color: ColorUtils.applyAlpha(ClockStyle.colPrimary, 0.35 + zoneRow.modelData.zone * 0.13)
                                }
                            }

                            StyledText {
                                Layout.preferredWidth: 52
                                horizontalAlignment: Text.AlignRight
                                text: VitalsTypes.duration(zoneRow.minutes)
                                font.pixelSize: ClockStyle.textSmall
                                font.weight: Font.DemiBold
                                color: ClockStyle.colOnSurface
                            }
                        }
                    }
                }
            }

            // ── Route ───────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                visible: sheet.hasRoute
                implicitHeight: Math.round(width * 0.8)
                radius: ClockStyle.radiusLarge
                color: ClockStyle.colField

                StyledText {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: ClockStyle.gap
                    text: Translation.tr("Route")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: ClockStyle.colOnSurfaceVariant
                }

                VitalsRouteLine {
                    anchors.fill: parent
                    anchors.margins: ClockStyle.gap
                    anchors.topMargin: ClockStyle.gap + 16
                    points: sheet.routePoints
                }

                StyledText {
                    anchors.centerIn: parent
                    width: parent.width - ClockStyle.gapHuge * 2
                    visible: sheet.routePoints === null
                    horizontalAlignment: Text.AlignHCenter
                    text: VitalsService.linked ? Translation.tr("Fetching the route from the phone…")
                        : Translation.tr("The route is still on the phone; it comes over when the phone is linked.")
                    wrapMode: Text.WordWrap
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colOnSurfaceVariant
                }
            }
        }
    }
}
