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

/**
 * Crashes: one lane per program on a shared seven-day axis, and a stage for the one you
 * pick.
 *
 * Package updates are lines that cross every lane, so "it started after that update"
 * shows without reading anything. Filled marks are your own programs, outlined marks
 * system programs (root). The selected lane squares its corners and its marks turn into
 * diamonds. The stage beside it is the world clock's hero-and-list pattern: the program
 * in the app's only wide light face, one sentence of what happened, the update it
 * followed, and the last steps before the crash as a literal stack with the frame where
 * it broke filled in the error colour. It has no side sheet: the stage is the detail.
 */
Item {
    id: root

    property double now: Date.now()
    property bool compact: false
    property real layoutWidth: root.width
    property HealthAssistant assistant: null

    readonly property var groups: Array.from(HealthService.crashGroups).sort((a, b) => (a.muted === b.muted ? 0 : a.muted ? 1 : -1) || Number(b.last ?? 0) - Number(a.last ?? 0))
    property string selectedExe: ""
    readonly property var selected: root.groups.find(g => g.exe === root.selectedExe) ?? root.groups[0] ?? null
    readonly property bool sideBySide: root.layoutWidth >= HealthStyle.sideBySideMin
    readonly property real stageWidth: root.sideBySide ? Math.round(Math.max(HealthStyle.stageMinWidth, Math.min(480, root.layoutWidth * 0.4))) : root.width

    readonly property int total: root.groups.filter(g => !g.muted).reduce((n, g) => n + Number(g.count ?? 0), 0)
    readonly property string pageSubtitle: root.groups.length === 0 ? Translation.tr("Last 7 days")
        : Translation.tr("%1 · %2 · last 7 days")
            .arg(HealthText.plural(root.total, Translation.tr("%1 crash"), Translation.tr("%1 crashes")))
            .arg(HealthText.plural(root.groups.length, Translation.tr("%1 program"), Translation.tr("%1 programs")))

    // The axis: the six days before today and today, local midnight to midnight.
    readonly property double axisStart: {
        const d = new Date(root.now);
        return new Date(d.getFullYear(), d.getMonth(), d.getDate() - 6).getTime();
    }
    readonly property double axisEnd: root.axisStart + 7 * 86400000

    function pos(t): real {
        return Math.max(0, Math.min(1, (Number(t) - root.axisStart) / (root.axisEnd - root.axisStart)));
    }

    function showFinding(id): void {
        const exe = String(id).replace(/^crash:/, "");
        if (root.groups.some(g => g.exe === exe))
            root.selectedExe = exe;
    }

    // Only the updates that touched a program on a lane are drawn; a rolling distribution
    // updates daily, and a line for every transaction would hide the ones that matter.
    readonly property var crashedPackages: root.groups.map(g => String(g.package ?? "")).filter(p => p.length > 0)
    readonly property var relevantUpdates: HealthService.updateTransactions.filter(tx =>
        Number(tx.time) >= root.axisStart && Array.from(tx.names ?? []).some(n => root.crashedPackages.includes(n)))

    // The label goes on one line only: the update the selected program's crashes followed.
    function updateLabel(tx): string {
        const g = root.selected;
        if (g?.afterUpdate && Math.abs(Number(g.afterUpdate.time) - Number(tx.time)) < 120000)
            return `${g.afterUpdate.name} ${g.afterUpdate.to ?? ""}`.trim();
        return "";
    }

    function touchesSelected(tx): bool {
        return !!root.selected?.package && Array.from(tx.names ?? []).includes(root.selected.package);
    }

    // Unsymbolised frames ("n/a", "??") in one module fold into a single step.
    function foldFrames(trace, own): var {
        const out = [];
        Array.from(trace ?? []).forEach((fr, i) => {
            const blank = !fr.fn || fr.fn === "n/a" || fr.fn === "??";
            const last = out[out.length - 1];
            if (blank && last && last.blank && last.module === fr.module && i !== own) {
                last.count += 1;
                return;
            }
            out.push({ fn: fr.fn, module: fr.module, blank: blank, count: 1, own: i === own });
        });
        return out;
    }

    Loader {
        anchors.fill: parent
        active: root.groups.length > 0
        sourceComponent: root.sideBySide ? sideLayout : stackLayout
    }

    ClockEmptyState {
        anchors.centerIn: parent
        visible: root.groups.length === 0 && HealthService.synced
        symbol: "heart_check"
        shape: "Clover4Leaf"
        title: Translation.tr("No crashes in 7 days")
        subtitle: HealthService.journalAccess === "user"
            ? Translation.tr("Only your own programs are visible. Join the systemd-journal group to see system crashes too.")
            : Translation.tr("A program that crashes shows up here, lined up against the updates.")
    }

    Component {
        id: sideLayout
        RowLayout {
            spacing: ClockStyle.paneGap

            Lanes {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }

            Stage {
                Layout.preferredWidth: root.stageWidth
                Layout.fillHeight: true
            }
        }
    }

    Component {
        id: stackLayout
        StyledFlickable {
            id: stackFlick
            contentWidth: width
            contentHeight: stackColumn.implicitHeight + ClockStyle.gapHuge
            clip: true

            ColumnLayout {
                id: stackColumn
                width: stackFlick.width
                spacing: ClockStyle.paneGap

                Lanes {
                    Layout.fillWidth: true
                }

                Stage {
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                }
            }
        }
    }

    // ── Lanes ───────────────────────────────────────────────────────────
    component Lanes: Rectangle {
        id: lanes

        readonly property real labelWidth: root.compact ? HealthStyle.laneLabelWidthCompact : HealthStyle.laneLabelWidth

        implicitHeight: lanesColumn.implicitHeight + ClockStyle.gapLarge * 2
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colPane

        StyledFlickable {
            anchors.fill: parent
            anchors.margins: ClockStyle.gapLarge
            contentWidth: width
            contentHeight: lanesColumn.implicitHeight
            clip: true
            interactive: contentHeight > height

            ColumnLayout {
                id: lanesColumn
                width: parent.width
                spacing: ClockStyle.gap

                RowLayout {
                    Layout.fillWidth: true

                    StyledText {
                        text: Translation.tr("Last 7 days")
                        font.pixelSize: ClockStyle.textSmall
                        font.weight: Font.Black
                        font.letterSpacing: 1.0
                        font.capitalization: Font.AllUppercase
                        color: ClockStyle.colSubtext
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    StyledText {
                        text: Translation.tr("Pick a lane")
                        font.pixelSize: ClockStyle.textSmall
                        color: ClockStyle.colSubtext
                    }
                }

                // Day labels over the tracks only.
                Item {
                    Layout.fillWidth: true
                    implicitHeight: dayRow.implicitHeight

                    Row {
                        id: dayRow
                        x: lanes.labelWidth + ClockStyle.gap
                        width: parent.width - x

                        Repeater {
                            model: 7
                            StyledText {
                                required property int index
                                width: dayRow.width / 7
                                text: index === 6 ? Translation.tr("Today") : HealthText.dayName(root.axisStart + index * 86400000, root.now)
                                font.pixelSize: ClockStyle.textSmall - 1
                                font.weight: Font.DemiBold
                                color: index === 6 ? ClockStyle.colPrimary : ClockStyle.colSubtext
                                leftPadding: 4
                            }
                        }
                    }
                }

                Item {
                    id: laneArea
                    Layout.fillWidth: true
                    implicitHeight: laneColumn.implicitHeight + 26

                    Column {
                        id: laneColumn
                        width: parent.width
                        spacing: ClockStyle.gap

                        Repeater {
                            model: ScriptModel {
                                values: root.groups
                                objectProp: "exe"
                            }

                            Lane {
                                required property var modelData
                                required property int index
                                width: laneColumn.width
                                group: modelData
                                labelWidth: lanes.labelWidth
                                entranceIndex: index
                            }
                        }
                    }

                    // Package updates: lines across every lane, labelled when the update
                    // touched a program that crashed afterwards.
                    Repeater {
                        model: root.relevantUpdates

                        Item {
                            id: upd
                            required property var modelData
                            readonly property string label: root.updateLabel(modelData)
                            readonly property bool mine: root.touchesSelected(modelData)
                            readonly property real trackWidth: laneArea.width - lanes.labelWidth - ClockStyle.gap
                            x: lanes.labelWidth + ClockStyle.gap + root.pos(modelData.time) * upd.trackWidth - 1
                            y: 0
                            width: 2
                            height: laneArea.height

                            Rectangle {
                                width: 2
                                height: laneColumn.implicitHeight + 4
                                radius: 1
                                color: ClockStyle.colPrimary
                                opacity: upd.mine ? 0.7 : 0.25

                                Behavior on opacity {
                                    animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                                }
                            }

                            Rectangle {
                                visible: upd.label.length > 0
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: laneColumn.implicitHeight + 6
                                implicitWidth: updText.implicitWidth + 14
                                implicitHeight: updText.implicitHeight + 4
                                radius: height / 2
                                color: ClockStyle.colPrimaryContainer

                                StyledText {
                                    id: updText
                                    anchors.centerIn: parent
                                    text: upd.label
                                    font.pixelSize: ClockStyle.textSmall - 2
                                    font.weight: Font.Bold
                                    color: ClockStyle.colOnPrimaryContainer
                                }
                            }

                            // A 2 px line is too thin to aim at: a wider strip around it
                            // takes the hover (a handler, so the lanes still get clicks).
                            Item {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 12
                                height: parent.height
                                HoverHandler {
                                    id: updHover
                                }
                            }

                            // Only on hover: an Item has no hover of its own, which a
                            // tooltip reads as always hovered.
                            StyledToolTip {
                                extraVisibleCondition: updHover.hovered
                                text: Translation.tr("%1 packages updated: %2").arg(upd.modelData.count).arg(Array.from(upd.modelData.names ?? []).slice(0, 8).join(", "))
                            }
                        }
                    }
                }

                // Legend, in words and in the marks' own shapes.
                Flow {
                    Layout.fillWidth: true
                    Layout.topMargin: ClockStyle.gapSmall
                    spacing: ClockStyle.gapLarge

                    LegendItem {
                        label: Translation.tr("Your program crashed")
                        Rectangle {
                            width: 10
                            height: 10
                            radius: 3
                            color: ClockStyle.colError
                        }
                    }
                    LegendItem {
                        label: Translation.tr("A system program crashed")
                        Rectangle {
                            width: 10
                            height: 10
                            radius: 3
                            color: "transparent"
                            border.width: 2
                            border.color: ClockStyle.colError
                        }
                    }
                    LegendItem {
                        label: Translation.tr("A package update")
                        Rectangle {
                            width: 3
                            height: 12
                            radius: 1
                            color: ClockStyle.colPrimary
                        }
                    }
                }
            }
        }
    }

    component LegendItem: Row {
        property string label: ""
        default property alias mark: markHolder.data
        spacing: 6

        Item {
            id: markHolder
            width: 12
            height: 12
            anchors.verticalCenter: parent.verticalCenter
        }
        StyledText {
            text: parent.label
            font.pixelSize: ClockStyle.textSmall
            color: ClockStyle.colSubtext
        }
    }

    component Lane: Item {
        id: lane

        property var group: null
        property real labelWidth: 160
        property int entranceIndex: 0
        readonly property bool isSelected: root.selected !== null && lane.group?.exe === root.selected.exe

        implicitHeight: HealthStyle.laneHeight
        opacity: lane.group?.muted ? 0.5 : 1

        StaggeredEntrance {
            index: lane.entranceIndex
            active: !ClockStyle.reducedMotion
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.selectedExe = lane.group.exe
        }

        RowLayout {
            width: lane.labelWidth
            anchors.verticalCenter: parent.verticalCenter
            spacing: ClockStyle.gapSmall

            StyledText {
                text: String(lane.group?.count ?? 0)
                font.family: ClockStyle.fontMain
                font.variableAxes: ({ "wght": 700, "wdth": 30, "ROND": 100 })
                font.pixelSize: 30
                font.features: { "tnum": 1 }
                color: lane.isSelected ? ClockStyle.colError : ClockStyle.colSubtext
                Layout.minimumWidth: 22

                Behavior on color {
                    animation: ClockStyle.motionFast.colorAnimation.createObject(this)
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: lane.group?.name ?? ""
                elide: Text.ElideRight
                font.pixelSize: ClockStyle.textNormal + 1
                font.variableAxes: ({ "wght": lane.isSelected ? 800 : 600, "wdth": 92 })
                color: ClockStyle.colOnSurface
            }

            HealthAnswerMark {
                assistant: root.assistant
                key: lane.group ? `crash:${lane.group.exe}` : ""
                color: ClockStyle.colOnSurface
            }
        }

        Rectangle {
            id: track
            x: lane.labelWidth + ClockStyle.gap
            width: lane.width - x
            height: HealthStyle.laneHeight
            radius: lane.isSelected ? ClockStyle.radiusSmall : height / 2
            color: lane.isSelected ? ClockStyle.colSecondaryContainer : trackHover.hovered ? ClockStyle.colRailRowHover : ClockStyle.colRailRow

            Behavior on radius {
                animation: ClockStyle.motionSpatial.numberAnimation.createObject(this)
            }
            Behavior on color {
                animation: ClockStyle.motionFast.colorAnimation.createObject(this)
            }

            HoverHandler {
                id: trackHover
            }

            Repeater {
                model: Array.from(lane.group?.events ?? [])

                // The mark's place, unrotated: the tooltip and the hover sit here, so
                // the selected lane's diamond (rotated, scaled) does not throw the
                // tooltip off to one side.
                Item {
                    id: mark
                    required property var modelData
                    readonly property bool system: Number(mark.modelData.uid ?? -1) === 0
                    width: 12
                    height: 12
                    x: Math.max(4, Math.min(track.width - 16, root.pos(mark.modelData.time) * track.width - 6))
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        anchors.fill: parent
                        radius: lane.isSelected ? 2 : 4
                        rotation: lane.isSelected ? 45 : 0
                        scale: lane.isSelected ? 1.25 : 1
                        color: mark.system ? "transparent" : ClockStyle.colError
                        border.width: mark.system ? 2.5 : 0
                        border.color: ClockStyle.colError

                        Behavior on rotation {
                            enabled: !ClockStyle.reducedMotion
                            animation: ClockStyle.motionSpatial.numberAnimation.createObject(this)
                        }
                        Behavior on scale {
                            enabled: !ClockStyle.reducedMotion
                            animation: ClockStyle.motionSpatial.numberAnimation.createObject(this)
                        }
                    }

                    HoverHandler {
                        id: markHover
                    }
                    // Only on hover: an Item has no hover of its own, which a tooltip
                    // reads as always hovered.
                    StyledToolTip {
                        extraVisibleCondition: markHover.hovered
                        text: `${HealthText.dayName(mark.modelData.time, root.now)} ${Qt.formatTime(new Date(Number(mark.modelData.time)), "hh:mm")} · ${HealthText.signalName(mark.modelData.signal)}`
                    }
                }
            }
        }
    }

    // ── Stage ───────────────────────────────────────────────────────────
    component Stage: Rectangle {
        id: stage

        readonly property var g: root.selected
        readonly property string key: `crash:${stage.g?.exe ?? ""}`
        property string busy: ""

        implicitHeight: stageColumn.implicitHeight + ClockStyle.cardPadding * 2
        radius: ClockStyle.radiusExtraLarge
        color: ClockStyle.colPane

        StyledFlickable {
            id: stageFlick
            anchors.fill: parent
            anchors.margins: ClockStyle.cardPadding
            contentWidth: width
            contentHeight: stageColumn.implicitHeight
            clip: true
            interactive: contentHeight > height

            ColumnLayout {
                id: stageColumn
                width: stageFlick.width
                spacing: ClockStyle.gap

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapTiny

                    StyledText {
                        Layout.fillWidth: true
                        text: [HealthText.plural(stage.g?.count ?? 0, Translation.tr("%1 crash"), Translation.tr("%1 crashes")),
                            stage.g?.root ? Translation.tr("system program") : Translation.tr("your program")].join(" · ")
                        elide: Text.ElideRight
                        font.pixelSize: ClockStyle.textSmall
                        font.weight: Font.Black
                        font.letterSpacing: 1.0
                        font.capitalization: Font.AllUppercase
                        color: ClockStyle.colSubtext
                    }

                    HealthAssistantButton {
                        visible: root.assistant !== null && root.assistant.allowed
                        assistant: root.assistant ?? stagePlaceholder
                        key: stage.key
                        provider: () => ({ crash: Object.assign({}, stage.g, { events: undefined }), meaning: HealthText.signalMeaning(stage.g?.signal) })
                    }
                    ClockIconButton {
                        symbol: stage.g?.muted ? "notifications_active" : "notifications_off"
                        tooltip: stage.g?.muted ? Translation.tr("Show crashes of this program again") : Translation.tr("Ignore crashes of this program")
                        onClicked: stage.g.muted ? HealthService.unmuteProgram(stage.g.exe) : HealthService.muteProgram(stage.g.exe)
                    }
                    ClockIconButton {
                        symbol: "done_all"
                        tooltip: Translation.tr("Hide until it crashes again")
                        onClicked: HealthService.dismiss(`crash:${stage.g.exe}`)
                    }
                }

                HealthAssistantPanel {
                    Layout.fillWidth: true
                    assistant: root.assistant ?? stagePlaceholder
                    key: stage.key
                    placeholder: Translation.tr("Ask about this crash — “why does it keep aborting?”")
                    provider: () => ({ crash: Object.assign({}, stage.g, { events: undefined }), meaning: HealthText.signalMeaning(stage.g?.signal) })
                }

                StyledText {
                    Layout.fillWidth: true
                    // Break long names at their hyphens, not mid-word.
                    text: String(stage.g?.name ?? "").replace(/-/g, "-​")
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.family: ClockStyle.fontMain
                    font.variableAxes: HealthStyle.axesWideLight
                    font.pixelSize: Math.round(Math.min(40, Math.max(26, stage.width * 0.085)))
                    lineHeight: 0.95
                    color: ClockStyle.colOnSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    textFormat: Text.StyledText
                    text: `<b>${HealthText.signalMeaning(stage.g?.signal)}</b>, ${HealthText.plural(stage.g?.count ?? 0, Translation.tr("%1 time"), Translation.tr("%1 times"))}. `
                        + Translation.tr("Last: %1, %2.").arg(HealthText.dayName(stage.g?.last, root.now)).arg(Qt.formatTime(new Date(Number(stage.g?.last ?? 0)), "hh:mm"))
                    wrapMode: Text.Wrap
                    font.pixelSize: ClockStyle.textNormal + 1
                    color: ClockStyle.colOnSurface
                }

                // The update it followed, or the package it belongs to.
                Rectangle {
                    Layout.alignment: Qt.AlignLeft
                    visible: !!stage.g?.afterUpdate || !!stage.g?.package
                    implicitWidth: corrRow.implicitWidth + 20
                    implicitHeight: 30
                    radius: 15
                    color: stage.g?.afterUpdate ? ClockStyle.colTertiaryContainer : ClockStyle.colSurfaceHigh

                    RowLayout {
                        id: corrRow
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            text: stage.g?.afterUpdate ? "update" : "package_2"
                            iconSize: 16
                            color: stage.g?.afterUpdate ? ClockStyle.colOnTertiaryContainer : ClockStyle.colOnSurfaceVariant
                        }
                        StyledText {
                            text: stage.g?.afterUpdate
                                ? Translation.tr("Began after %1 %2 · %3").arg(stage.g.afterUpdate.name).arg(stage.g.afterUpdate.to ?? "").arg(HealthText.dayName(stage.g.afterUpdate.time, root.now))
                                : `${stage.g?.package ?? ""} ${stage.g?.version ?? ""}`
                            font.pixelSize: ClockStyle.textSmall
                            font.weight: Font.Bold
                            color: stage.g?.afterUpdate ? ClockStyle.colOnTertiaryContainer : ClockStyle.colOnSurfaceVariant
                        }
                    }
                }

                HealthExplainCard {
                    Layout.fillWidth: true
                    explanation: stage.g ? HealthText.explainCrash(stage.g) : null
                }

                // The last steps before the crash, as a literal stack: the crash point at
                // the top, the frame where it broke filled in the error colour.
                StyledText {
                    Layout.topMargin: ClockStyle.gapSmall
                    visible: (stage.g?.trace ?? []).length > 0
                    text: Translation.tr("Last steps before the crash")
                    font.pixelSize: ClockStyle.textSmall - 1
                    font.weight: Font.Black
                    font.letterSpacing: 0.8
                    font.capitalization: Font.AllUppercase
                    color: ClockStyle.colSubtext
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    Repeater {
                        model: root.foldFrames(stage.g?.trace, Number(stage.g?.ownFrame ?? -1)).slice(0, 8)

                        Rectangle {
                            id: frame
                            required property var modelData
                            required property int index
                            readonly property bool own: modelData.own === true
                            Layout.fillWidth: true
                            implicitHeight: frameText.implicitHeight + 12
                            radius: frame.own ? 14 : 6
                            color: frame.own ? ClockStyle.colErrorContainer : ClockStyle.colRailRow

                            StyledText {
                                id: frameText
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: 12
                                    rightMargin: 12
                                }
                                textFormat: Text.StyledText
                                text: (frame.own ? `<b>${Translation.tr("where it broke")}</b> · ` : "")
                                    + (frame.modelData.blank
                                        ? (frame.modelData.count > 1 ? Translation.tr("%1 unnamed steps").arg(frame.modelData.count) : Translation.tr("an unnamed step"))
                                        : String(frame.modelData.fn ?? "??").replace(/</g, "&lt;"))
                                    + ` <font color="${frame.own ? ClockStyle.colOnErrorContainer : ClockStyle.colSubtext}">· ${frame.modelData.module ?? ""}</font>`
                                elide: Text.ElideRight
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: ClockStyle.textSmall
                                color: frame.own ? ClockStyle.colOnErrorContainer : ClockStyle.colOnSurfaceVariant
                            }
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: stage.g?.root === true && HealthService.dumpAccess !== "granted"
                    text: Translation.tr("The full dump is readable only by root. Allow your account in Settings to debug it; the stack trace above comes from the journal.")
                    wrapMode: Text.Wrap
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colSubtext
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: ClockStyle.gapSmall
                    spacing: ClockStyle.gapSmall

                    ClockSheetAction {
                        label: Translation.tr("Debug in a terminal")
                        symbol: "terminal"
                        enabled: !(stage.g?.root === true && HealthService.dumpAccess !== "granted")
                        onClicked: HealthService.runInTerminal(["coredumpctl", "gdb", stage.g.exe])
                    }
                    ClockSheetAction {
                        primary: true
                        label: stage.busy === "copied" ? Translation.tr("Copied") : Translation.tr("Copy report")
                        symbol: stage.busy === "copied" ? "check" : "content_copy"
                        onClicked: HealthService.copyCrashReport(stage.g.exe, () => {
                            stage.busy = "copied";
                            copiedTimer.restart();
                        })
                    }
                }

                Timer {
                    id: copiedTimer
                    interval: 2000
                    onTriggered: stage.busy = ""
                }
            }
        }

        HealthAssistant {
            id: stagePlaceholder
        }
    }
}
