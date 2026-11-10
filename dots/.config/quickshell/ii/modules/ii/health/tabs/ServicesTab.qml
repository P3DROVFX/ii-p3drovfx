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
 * Services: every failed unit, restart loop and failed app launch.
 *
 * One grouped list, the rail's shape: outer corners large, joins small, and the open
 * row turns into a pill that presses a notch into its neighbours. Actions slide in from
 * the right on hover (the ToDo pattern), tinted with the row's own content colour.
 */
Item {
    id: root

    property double now: Date.now()
    property bool compact: false
    property real layoutWidth: root.width
    property ClockSidePanel panels: null
    property HealthAssistant assistant: null

    property string filter: "failed"
    readonly property var all: HealthService.findingsOfKind(["unit", "restartLoop", "appLaunch"])
    readonly property var filters: [
        { id: "failed", label: Translation.tr("Failed"), match: f => f.kind === "unit" },
        { id: "loops", label: Translation.tr("Restart loops"), match: f => f.kind === "restartLoop" },
        { id: "apps", label: Translation.tr("App launches"), match: f => f.kind === "appLaunch" },
        { id: "system", label: Translation.tr("System"), match: f => f.data?.scope === "system" },
        { id: "user", label: Translation.tr("User"), match: f => f.data?.scope === "user" }
    ]
    readonly property var rows: {
        const flt = root.filters.find(x => x.id === root.filter) ?? root.filters[0];
        return root.all.filter(flt.match);
    }
    readonly property string openId: root.panels?.open ? String(root.panels.current?.findingId ?? "") : ""

    readonly property string pageSubtitle: {
        const failed = root.all.filter(f => f.kind === "unit").length;
        const loops = root.all.filter(f => f.kind === "restartLoop").length;
        return Translation.tr("%1 failed · %2 restarting in a loop").arg(failed).arg(loops);
    }

    // Land on whichever list has something in it, the first time the page opens.
    Component.onCompleted: {
        for (const flt of root.filters) {
            if (root.all.some(flt.match)) {
                root.filter = flt.id;
                break;
            }
        }
    }

    function showFinding(id): void {
        const f = HealthService.finding(id);
        if (!f)
            return;
        const flt = root.filters.find(x => x.match(f));
        if (flt && !root.filters.find(x => x.id === root.filter).match(f))
            root.filter = flt.id;
        root.open(id);
    }

    function open(id): void {
        root.panels?.show(findingSheet, { findingId: id, assistant: root.assistant });
    }

    /// A row's click: the open row's second click closes its sheet.
    function toggle(id): void {
        if (root.openId === id)
            root.panels.close();
        else
            root.open(id);
    }

    /// Keyboard, from the app: ↑ ↓ (k j) open the previous or next row's sheet, so
    /// the open row's pill is the focus; Enter opens or closes it; a asks the
    /// assistant about it, s shows its snooze choices.
    function handleNavKey(event): bool {
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier) || root.rows.length === 0)
            return false;
        const cur = root.rows.findIndex(f => f.id === root.openId);
        const sheet = root.panels?.open ? root.panels.current : null;
        switch (event.key) {
        case Qt.Key_Down:
        case Qt.Key_J:
            root.open(root.rows[Math.min(root.rows.length - 1, cur + 1)].id);
            return true;
        case Qt.Key_Up:
        case Qt.Key_K:
            root.open(root.rows[Math.max(0, cur - 1)].id);
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (cur >= 0)
                root.panels.close();
            else
                root.open(root.rows[0].id);
            return true;
        case Qt.Key_A:
            if (cur < 0 || typeof sheet?.askAssistant !== "function")
                return false;
            sheet.askAssistant();
            return true;
        case Qt.Key_S:
            if (cur < 0 || !sheet)
                return false;
            sheet.snoozeOpen = !sheet.snoozeOpen;
            return true;
        }
        return false;
    }

    function run(f, verb): void {
        HealthService.runAction(f.id, verb);
    }

    Component {
        id: findingSheet
        FindingSheet {}
    }

    StyledFlickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight + ClockStyle.gapHuge * 2
        clip: true

        ColumnLayout {
            id: column
            width: flick.width
            spacing: ClockStyle.gap

            Flow {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                Repeater {
                    model: root.filters

                    ClockFormChip {
                        required property var modelData
                        readonly property int n: root.all.filter(modelData.match).length
                        label: n > 0 ? `${modelData.label} ${n}` : modelData.label
                        selected: root.filter === modelData.id
                        onTriggered: root.filter = modelData.id
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                visible: root.rows.length > 0

                Repeater {
                    model: ScriptModel {
                        values: root.rows
                        objectProp: "id"
                    }

                    UnitRow {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        finding: modelData
                        first: index === 0
                        last: index === root.rows.length - 1
                        selected: root.openId === modelData.id
                        prevSelected: index > 0 && root.openId === root.rows[index - 1].id
                        nextSelected: index < root.rows.length - 1 && root.openId === root.rows[index + 1].id
                        entranceIndex: index
                    }
                }
            }

            ClockEmptyState {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: ClockStyle.gapHuge * 2
                visible: root.rows.length === 0 && HealthService.synced
                symbol: "check_circle"
                shape: "Cookie9Sided"
                title: root.filter === "apps" ? Translation.tr("Every app started") : Translation.tr("Every service is running")
                subtitle: root.filter === "loops" ? Translation.tr("Nothing is restarting over and over.")
                    : Translation.tr("A service that fails shows up here, with why in plain words.")
            }
        }
    }

    component UnitRow: Rectangle {
        id: row

        property var finding: null
        property bool first: false
        property bool last: false
        property bool selected: false
        property bool prevSelected: false
        property bool nextSelected: false
        property int entranceIndex: 0

        readonly property var d: row.finding?.data ?? ({})
        readonly property bool engaged: rowHover.hovered || row.selected
        readonly property color colContent: row.selected ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface
        property real revealProgress: row.engaged ? 1 : 0
        readonly property real endRadius: ClockStyle.radiusLarge
        readonly property real joinRadius: Appearance.rounding.verysmall
        readonly property real pillRadius: Math.min(row.height / 2, ClockStyle.radiusLarge)

        Behavior on revealProgress {
            animation: ClockStyle.motionFast.numberAnimation.createObject(this)
        }

        implicitHeight: Math.max(64, rowLayout.implicitHeight + ClockStyle.gap * 2)
        color: row.selected ? ClockStyle.colSecondaryContainer : rowHover.hovered ? ClockStyle.colRailRowHover : ClockStyle.colPane
        topLeftRadius: row.selected || row.prevSelected ? row.pillRadius : row.first ? row.endRadius : row.joinRadius
        topRightRadius: row.topLeftRadius
        bottomLeftRadius: row.selected || row.nextSelected ? row.pillRadius : row.last ? row.endRadius : row.joinRadius
        bottomRightRadius: row.bottomLeftRadius

        Behavior on color {
            animation: ClockStyle.motionFast.colorAnimation.createObject(this)
        }
        Behavior on topLeftRadius {
            animation: ClockStyle.motionSpatial.numberAnimation.createObject(this)
        }
        Behavior on bottomLeftRadius {
            animation: ClockStyle.motionSpatial.numberAnimation.createObject(this)
        }

        StaggeredEntrance {
            index: row.entranceIndex
            active: !ClockStyle.reducedMotion
        }

        HoverHandler {
            id: rowHover
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggle(row.finding.id)
        }

        RowLayout {
            id: rowLayout
            anchors {
                fill: parent
                leftMargin: ClockStyle.cardPadding
                rightMargin: ClockStyle.gapLarge
            }
            spacing: ClockStyle.gapLarge

            // State mark: a diamond for a failure, a circle for an app launch, a square
            // for a loop — read at a glance down the list, without colour alone.
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 10
                implicitHeight: 10
                radius: row.finding?.kind === "appLaunch" ? 5 : 2
                rotation: row.finding?.kind === "unit" ? 45 : 0
                color: row.finding?.kind === "appLaunch" ? ClockStyle.colTertiary : ClockStyle.colError
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: row.d.description && row.d.description.length > 0 ? row.d.description : HealthText.unitName(row.d.unit)
                    elide: Text.ElideRight
                    font.family: ClockStyle.fontTitle
                    font.variableAxes: ClockStyle.axesTitle
                    font.pixelSize: ClockStyle.textLarge
                    color: row.colContent
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: !rowStatus.visible
                    text: [row.d.unit, row.d.scope === "user" ? Translation.tr("user") : Translation.tr("system"),
                        row.finding?.kind === "restartLoop" ? Translation.tr("%1 restarts in 10 minutes").arg(row.d.nRestarts ?? 0) : HealthText.unitWhy(row.d)].join(" · ")
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textSmall
                    color: row.colContent
                    opacity: 0.75
                }

                // While an action runs, and after one that did not fix it.
                HealthActionStatus {
                    id: rowStatus
                    Layout.fillWidth: true
                    findingId: row.finding?.id ?? ""
                    colContent: row.colContent
                }
            }

            // The hover slot: width and the actions' arrival follow one progress.
            Item {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: actionRow.implicitWidth * row.revealProgress
                Layout.preferredHeight: actionRow.implicitHeight
                clip: true

                RowLayout {
                    id: actionRow
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: ClockStyle.gapTiny
                    opacity: row.revealProgress
                    enabled: !rowStatus.busy

                    ClockCardAction {
                        visible: row.finding?.kind !== "appLaunch"
                        symbol: row.finding?.kind === "restartLoop" ? "stop" : "restart_alt"
                        tip: row.finding?.kind === "restartLoop" ? Translation.tr("Stop") : Translation.tr("Restart")
                        colContent: row.colContent
                        onClicked: root.run(row.finding, row.finding.kind === "restartLoop" ? "stop" : "restart")
                    }
                    ClockCardAction {
                        symbol: "done_all"
                        tip: row.finding?.kind === "appLaunch" ? Translation.tr("Hide until it happens again") : Translation.tr("Clear the failure")
                        colContent: row.colContent
                        onClicked: row.finding.kind === "appLaunch" ? HealthService.dismiss(row.finding.id) : root.run(row.finding, "resetFailed")
                    }
                    ClockCardAction {
                        visible: row.finding?.kind === "unit"
                        symbol: "block"
                        tip: Translation.tr("Disable")
                        danger: true
                        onClicked: root.run(row.finding, "disable")
                    }
                }
            }

            HealthAnswerMark {
                Layout.alignment: Qt.AlignVCenter
                assistant: root.assistant
                key: HealthService.answerKey(row.finding)
                color: row.colContent
            }

            StyledText {
                Layout.alignment: Qt.AlignVCenter
                text: HealthText.age(row.finding?.since, root.now)
                font.pixelSize: ClockStyle.textSmall
                font.features: { "tnum": 1 }
                color: row.colContent
                opacity: 0.75
            }
        }
    }
}
