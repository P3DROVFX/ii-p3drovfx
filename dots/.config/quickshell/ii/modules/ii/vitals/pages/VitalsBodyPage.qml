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
import qs.modules.ii.usage
import qs.modules.ii.vitals.components

/**
 * Body: the body-composition measurements on a calendar timeline (one field at a time,
 * picked with chips) beside the list of measurements, the nightly skin temperature against
 * its 14-night baseline, and a tile per other body type. Every measurement opens a sheet
 * with all of its fields. Old measurements stay, with less weight.
 */
VitalsPage {
    id: root

    readonly property string today: VitalsFormat.dateOf(root.now)
    readonly property var present: VitalsService.present

    // ── Body composition ────────────────────────────────────────────────
    /// Oldest first: [{date, entry}], the day's last measurement as the index keeps it.
    readonly property var entries: {
        VitalsService.dataVersion;
        if (!root.present.body)
            return [];
        const out = [];
        for (const d of VitalsService.dates) {
            const m = VitalsService.summary(d)?.m?.body;
            if (m)
                out.push({ date: d, entry: m });
        }
        return out;
    }
    readonly property var fieldOrder: Object.keys(VitalsTypes.fields)
    /// The numeric fields any measurement has, in the registry's order.
    readonly property var bodyFields: {
        const have = {};
        for (const e of root.entries)
            for (const f in e.entry)
                if (f !== "time" && typeof e.entry[f] === "number")
                    have[f] = true;
        return Object.keys(have).sort((a, b) => {
            const ia = root.fieldOrder.indexOf(a), ib = root.fieldOrder.indexOf(b);
            return (ia < 0 ? 999 : ia) - (ib < 0 ? 999 : ib) || a.localeCompare(b);
        });
    }
    property string pickedField: ""
    readonly property string field: root.bodyFields.includes(root.pickedField) ? root.pickedField : (root.bodyFields[0] ?? "")
    readonly property var points: root.entries.filter(e => typeof e.entry[root.field] === "number").map(e => ({ date: e.date, value: e.entry[root.field] }))
    readonly property var lastEntry: root.entries.length > 0 ? root.entries[root.entries.length - 1] : null

    // ── Skin temperature, night by night ────────────────────────────────
    readonly property string skinKey: root.present.skinTempC ? "skinTempC" : root.present.skinTempDeltaC ? "skinTempDeltaC" : ""
    readonly property var nights: {
        VitalsService.dataVersion;
        if (root.skinKey === "")
            return [];
        const all = VitalsService.series(root.skinKey);
        if (all.length === 0)
            return [];
        const byDate = {};
        for (const p of all)
            byDate[p.date] = p.value;
        const end = all[all.length - 1].date;
        const out = [];
        for (let i = 29; i >= 0; i--) {
            const d = VitalsFormat.addDays(end, -i);
            const v = byDate[d];
            let delta = null, nights = 0;
            if (v !== undefined && root.skinKey === "skinTempDeltaC") {
                delta = v;
            } else if (v !== undefined) {
                // The 14 nights before this one; a baseline from fewer than three is noise.
                let sum = 0;
                for (let k = 1; k <= 14; k++) {
                    const b = byDate[VitalsFormat.addDays(d, -k)];
                    if (b !== undefined) {
                        sum += b;
                        nights++;
                    }
                }
                delta = nights >= 3 ? v - sum / nights : null;
            }
            out.push({ date: d, value: v ?? null, delta: delta, nights: nights });
        }
        return out;
    }
    readonly property var lastNight: {
        for (let i = root.nights.length - 1; i >= 0; i--)
            if (root.nights[i].value !== null)
                return root.nights[i];
        return null;
    }

    readonly property var otherKeys: VitalsTypes.keysFor("body", root.present).filter(k => !["body", "skinTempC", "skinTempDeltaC"].includes(k))

    readonly property var fieldIcons: ({
        weightKg: "monitor_weight", bodyFatPct: "percent", skeletalMuscleKg: "accessibility_new",
        leanMassKg: "accessibility_new", boneMassKg: "skeleton", bodyWaterKg: "water_drop",
        bmrKcal: "local_fire_department", bmi: "calculate", m: "height", c: "thermostat",
        site: "location_on", systolic: "arrow_upward", diastolic: "arrow_downward", pulse: "favorite"
    })

    /// Rounded before formatting, so a change too small to show reads 0.0 rather than −0.0.
    function rounded(delta: real): real {
        return Math.round(delta * 10) / 10 + 0;
    }

    function openMeasurement(key: string, date: string, entry: var): void {
        if (entry)
            root.panels.show(measurementSheet, { key: key, date: date, entry: entry });
    }

    function showingDate(key: string): string {
        return root.panels?.isShowing(measurementSheet) && root.panels.current?.key === key ? root.panels.current.date : "";
    }

    pageSubtitle: {
        const parts = [];
        if (root.lastEntry)
            parts.push(Translation.tr("Last measured %1").arg(VitalsFormat.dayLabel(root.lastEntry.date, root.now)));
        if (root.lastNight)
            parts.push(Translation.tr("skin temperature as of %1").arg(VitalsFormat.dayLabel(root.lastNight.date, root.now)));
        return parts.join(" · ");
    }

    function handleKey(key: int, modifiers: int): bool {
        // Ctrl/Alt/Super combinations are the window's (page switching, close, settings).
        if (modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
            return false;
        // ←/→ walk the measurements, opening each in the sheet.
        if ((key === Qt.Key_Left || key === Qt.Key_Right) && root.entries.length > 0) {
            const at = root.entries.findIndex(e => e.date === root.showingDate("body"));
            const next = at < 0 ? root.entries.length - 1 : Math.max(0, Math.min(root.entries.length - 1, at + (key === Qt.Key_Left ? -1 : 1)));
            root.openMeasurement("body", root.entries[next].date, root.entries[next].entry);
            return true;
        }
        if ((key === Qt.Key_Return || key === Qt.Key_Enter) && root.lastEntry) {
            root.openMeasurement("body", root.lastEntry.date, root.lastEntry.entry);
            return true;
        }
        return false;
    }

    // ── Layout ──────────────────────────────────────────────────────────
    readonly property real gap: ClockStyle.gap
    readonly property real contentWidth: root.width - ClockStyle.gapTiny * 2
    readonly property real contentLayoutWidth: root.layoutWidth - ClockStyle.gapTiny * 2
    readonly property bool sideBySide: !root.compact && root.contentLayoutWidth >= 820
    readonly property real listWidth: root.sideBySide ? Math.round(Math.min(340, root.contentLayoutWidth * 0.32)) : root.contentLayoutWidth
    readonly property int columns: root.compact ? 1 : Math.max(1, Math.floor((root.contentLayoutWidth + root.gap) / (VitalsStyle.tileMinWidth + root.gap)))
    readonly property real tileWidth: Math.floor((root.contentLayoutWidth - root.gap * (root.columns - 1)) / root.columns)

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

            // ── Timeline of one field ───────────────────────────────────
            Rectangle {
                id: timelinePane
                visible: root.entries.length > 0
                width: root.sideBySide ? Math.floor(root.contentLayoutWidth - root.listWidth - root.gap) : Math.floor(root.contentLayoutWidth)
                height: root.compact ? 360 : 400
                radius: VitalsStyle.radiusTile
                color: VitalsStyle.colTile

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
                            text: "monitor_weight"
                            iconSize: 18
                            padding: 9
                            shape: MaterialShape.Shape.Cookie6Sided
                            color: ClockStyle.colSecondaryContainer
                            colSymbol: ClockStyle.colOnSecondaryContainer
                            fill: 1
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: VitalsTypes.label("body")
                            elide: Text.ElideRight
                            font.pixelSize: ClockStyle.textNormal + 1
                            font.weight: Font.DemiBold
                            color: VitalsStyle.colOnTile
                        }

                        StyledText {
                            text: Translation.tr("%1 measurements").arg(root.entries.length)
                            font.pixelSize: ClockStyle.textSmall
                            color: VitalsStyle.colOnTileVariant
                        }
                    }

                    Flow {
                        Layout.fillWidth: true
                        visible: root.bodyFields.length > 1
                        spacing: ClockStyle.gapSmall

                        Repeater {
                            model: ScriptModel {
                                values: root.bodyFields
                            }

                            ClockFormChip {
                                required property var modelData
                                label: VitalsTypes.fieldLabel(String(modelData))
                                selected: String(modelData) === root.field
                                onTriggered: root.pickedField = String(modelData)
                            }
                        }
                    }

                    // The newest value and how it moved since the one before; old data dims.
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: ClockStyle.gapSmall
                        opacity: VitalsStyle.emphasis(root.points[root.points.length - 1]?.date ?? "", root.today)

                        Behavior on opacity {
                            animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ClockStyle.gapLarge

                            UsageFigure {
                                text: root.points.length > 0 ? VitalsTypes.formatField(root.field, root.points[root.points.length - 1].value) : "–"
                                size: root.compact ? 44 : 56
                                color: VitalsStyle.colOnTile
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignBottom
                                Layout.bottomMargin: 8
                                text: {
                                    const n = root.points.length;
                                    if (n === 0)
                                        return "";
                                    const last = root.points[n - 1];
                                    const head = Translation.tr("on %1").arg(VitalsFormat.dayLabel(last.date, root.now));
                                    if (n < 2)
                                        return head;
                                    const prev = root.points[n - 2];
                                    const d = Math.round((last.value - prev.value) * 10) / 10 + 0;
                                    const change = (d > 0 ? "+" : d < 0 ? "−" : "±") + VitalsTypes.formatField(root.field, Math.abs(d));
                                    return Translation.tr("%1 · %2 since %3").arg(head).arg(change).arg(VitalsFormat.dayLabel(prev.date, root.now));
                                }
                                elide: Text.ElideRight
                                font.pixelSize: ClockStyle.textNormal
                                color: VitalsStyle.colOnTileVariant
                            }
                        }

                        VitalsBodyTimelineChart {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            points: root.points
                            now: root.now
                            selectedIndex: root.points.findIndex(p => p.date === root.showingDate("body"))
                            colLine: ClockStyle.colPrimary
                            colContent: VitalsStyle.colOnTile
                            formatValue: v => VitalsTypes.formatField(root.field, v)
                            onPointClicked: index => {
                                const e = root.entries.find(x => x.date === root.points[index].date);
                                root.openMeasurement("body", e.date, e.entry);
                            }
                        }
                    }
                }
            }

            // ── Every measurement, newest first ─────────────────────────
            Rectangle {
                id: listPane
                visible: root.entries.length > 0
                width: Math.floor(root.listWidth)
                // Stacked, it shows whole rows (six at most) and scrolls for the rest.
                height: root.sideBySide ? timelinePane.height
                    : Math.min(root.entries.length, 6) * (58 + ClockStyle.gapTiny) - ClockStyle.gapTiny + ClockStyle.gapSmall * 2
                radius: VitalsStyle.radiusTile
                color: VitalsStyle.colTile
                clip: true

                StaggeredEntrance {
                    index: 1
                    active: !ClockStyle.reducedMotion
                }

                StyledFlickable {
                    anchors.fill: parent
                    anchors.margins: ClockStyle.gapSmall
                    contentWidth: width
                    contentHeight: listColumn.implicitHeight
                    clip: true

                    ColumnLayout {
                        id: listColumn
                        width: parent.width
                        spacing: ClockStyle.gapTiny

                        Repeater {
                            model: ScriptModel {
                                values: root.entries.slice().reverse()
                            }

                            RippleButton {
                                id: row
                                required property var modelData
                                readonly property bool showing: root.showingDate("body") === row.modelData.date
                                readonly property var entry: row.modelData.entry

                                Layout.fillWidth: true
                                implicitHeight: 58
                                buttonRadius: ClockStyle.radiusSmall
                                colBackground: row.showing ? ClockStyle.colSecondaryContainer : Appearance.colors.colLayer2
                                colBackgroundHover: row.showing ? ClockStyle.colSecondaryContainerHover : Appearance.colors.colLayer2Hover
                                colRipple: row.showing ? ClockStyle.colSecondaryContainerActive : Appearance.colors.colLayer2Active
                                onClicked: root.openMeasurement("body", row.modelData.date, row.entry)

                                contentItem: ColumnLayout {
                                    spacing: 0
                                    opacity: VitalsStyle.emphasis(row.modelData.date, root.today)

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.leftMargin: ClockStyle.gap
                                        Layout.rightMargin: ClockStyle.gap
                                        text: VitalsFormat.dayLabel(row.modelData.date, root.now)
                                            + (row.entry.time ? " · " + VitalsFormat.clock(row.entry.time) : "")
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.Bold
                                        color: row.showing ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurfaceVariant
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.leftMargin: ClockStyle.gap
                                        Layout.rightMargin: ClockStyle.gap
                                        text: root.bodyFields.filter(f => typeof row.entry[f] === "number").slice(0, 3)
                                            .map(f => VitalsTypes.formatField(f, row.entry[f])).join(" · ")
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.Bold
                                        color: row.showing ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Skin temperature against its baseline ───────────────────
            Rectangle {
                id: skinPane
                visible: root.lastNight !== null
                width: Math.floor(root.contentLayoutWidth)
                height: root.compact ? 300 : 320
                radius: VitalsStyle.radiusTile
                color: VitalsStyle.colTile

                StaggeredEntrance {
                    index: 2
                    active: !ClockStyle.reducedMotion
                }

                ColumnLayout {
                    anchors {
                        fill: parent
                        margins: VitalsStyle.tilePadding
                    }
                    spacing: ClockStyle.gap
                    opacity: VitalsStyle.emphasis(root.lastNight?.date ?? "", root.today)

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapSmall

                        MaterialSymbol {
                            text: "thermostat"
                            iconSize: ClockStyle.iconSmall + 2
                            fill: 1
                            color: VitalsStyle.colOnTile
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Skin temperature, night by night")
                            elide: Text.ElideRight
                            font.pixelSize: ClockStyle.textNormal
                            font.weight: Font.DemiBold
                            color: VitalsStyle.colOnTile
                        }

                        StyledText {
                            text: root.lastNight ? VitalsFormat.dayLabel(root.lastNight.date, root.now) : ""
                            font.pixelSize: ClockStyle.textSmall
                            color: VitalsStyle.colOnTileVariant
                            opacity: 0.8
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapLarge

                        // Wide display digits: this pane's number is a difference, not an amount.
                        StyledText {
                            text: root.lastNight?.delta !== null && root.lastNight?.delta !== undefined
                                ? VitalsTypes.format("skinTempDeltaC", root.rounded(root.lastNight.delta))
                                : VitalsTypes.format(root.skinKey, root.lastNight?.value ?? null)
                            font.family: ClockStyle.fontMain
                            font.variableAxes: ClockStyle.axesDisplay
                            font.pixelSize: root.compact ? 36 : 44
                            color: VitalsStyle.colOnTile
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignBottom
                            Layout.bottomMargin: 6
                            text: {
                                const n = root.lastNight;
                                if (!n)
                                    return "";
                                if (root.skinKey === "skinTempDeltaC")
                                    return Translation.tr("last night, as the phone reports the change");
                                if (n.delta === null)
                                    return Translation.tr("%1 last night · a baseline needs three nights before it").arg(VitalsTypes.format("skinTempC", n.value));
                                return Translation.tr("%1 last night · vs the %2 nights before it").arg(VitalsTypes.format("skinTempC", n.value)).arg(n.nights);
                            }
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            font.pixelSize: ClockStyle.textNormal
                            color: VitalsStyle.colOnTileVariant
                        }
                    }

                    VitalsBodyDeviationChart {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        items: root.nights.map(n => ({
                            label: String(Number(n.date.slice(8, 10))),
                            delta: n.delta,
                            tip: n.value === null ? Translation.tr("%1 · no reading").arg(VitalsFormat.dayLabel(n.date, root.now))
                                : n.delta === null ? Translation.tr("%1 · %2 · no baseline yet").arg(VitalsFormat.dayLabel(n.date, root.now)).arg(VitalsTypes.format(root.skinKey, n.value))
                                : Translation.tr("%1 · %2 · %3").arg(VitalsFormat.dayLabel(n.date, root.now))
                                    .arg(VitalsTypes.format(root.skinKey === "skinTempC" ? "skinTempC" : "skinTempDeltaC", n.value))
                                    .arg(VitalsTypes.format("skinTempDeltaC", root.rounded(n.delta)))
                        }))
                        selectedIndex: root.nights.length - 1
                        colContent: VitalsStyle.colOnTile
                        formatValue: v => VitalsTypes.format("skinTempDeltaC", v)
                    }
                }
            }

            // ── Other body types ────────────────────────────────────────
            Repeater {
                model: ScriptModel {
                    values: root.otherKeys
                }

                VitalsTile {
                    id: tile
                    required property var modelData
                    required property int index
                    readonly property string key: String(tile.modelData)
                    readonly property var last: {
                        VitalsService.dataVersion;
                        return VitalsService.latest(tile.key);
                    }

                    width: root.tileWidth
                    height: Math.round((VitalsStyle.tileHeightMin - root.gap) / 2) + 30
                    entranceIndex: 3 + tile.index
                    symbol: VitalsTypes.icon(tile.key)
                    title: VitalsTypes.label(tile.key)
                    asOf: tile.last ? VitalsFormat.asOf(tile.last.time, tile.last.date, root.now) : ""
                    emphasis: VitalsStyle.emphasis(tile.last?.date ?? "", root.today)
                    onClicked: {
                        if (tile.last && typeof tile.last.value === "object")
                            root.openMeasurement(tile.key, tile.last.date, tile.last.value);
                    }

                    StyledText {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        text: tile.last ? VitalsTypes.format(tile.key, tile.last.value) : ""
                        elide: Text.ElideRight
                        font.family: ClockStyle.fontTitle
                        font.variableAxes: ClockStyle.axesTitle
                        font.pixelSize: ClockStyle.textTitle + 4
                        color: tile.colContent
                    }
                }
            }
        }
    }

    // ── A measurement: every field ──────────────────────────────────────
    Component {
        id: measurementSheet

        ClockSheet {
            id: sheet
            property string key: ""
            property string date: ""
            property var entry: null
            readonly property var fieldNames: Object.keys(sheet.entry ?? {}).filter(f => f !== "time").sort((a, b) => {
                const ia = root.fieldOrder.indexOf(a), ib = root.fieldOrder.indexOf(b);
                return (ia < 0 ? 999 : ia) - (ib < 0 ? 999 : ib) || a.localeCompare(b);
            })
            readonly property var shapes: [MaterialShape.Shape.Cookie12Sided, MaterialShape.Shape.Clover4Leaf,
                MaterialShape.Shape.Cookie7Sided, MaterialShape.Shape.Sunny, MaterialShape.Shape.Cookie9Sided,
                MaterialShape.Shape.SoftBurst, MaterialShape.Shape.Flower, MaterialShape.Shape.Cookie6Sided]

            title: VitalsTypes.label(sheet.key)
            subtitle: VitalsFormat.dayLabel(sheet.date, root.now) + (sheet.entry?.time ? " · " + VitalsFormat.clock(sheet.entry.time) : "")

            Repeater {
                model: ScriptModel {
                    values: sheet.fieldNames
                }

                VitalsFactRow {
                    required property var modelData
                    required property int index
                    symbol: root.fieldIcons[String(modelData)] ?? "straighten"
                    shapeKind: sheet.shapes[index % sheet.shapes.length]
                    caption: VitalsTypes.fieldLabel(String(modelData))
                    value: VitalsTypes.formatField(String(modelData), sheet.entry[String(modelData)])
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: VitalsFormat.daysBetween(sheet.date, root.today) > VitalsStyle.staleDays
                text: Translation.tr("Measured %1 days ago").arg(VitalsFormat.daysBetween(sheet.date, root.today))
                font.pixelSize: ClockStyle.textSmall
                color: ClockStyle.colSubtext
            }
        }
    }
}
