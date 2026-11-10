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
 * Journal: error messages grouped by what they say, with the noise put away.
 *
 * Text first: the message template in monospace, where it came from, how often it shows
 * up in words ("every boot", "this boot only") and the count in tall digits. The noise
 * figure is the app's only thin number — quiet on purpose, because what it counts is
 * what the app decided not to bother you with.
 */
Item {
    id: root

    property double now: Date.now()
    property bool compact: false
    property real layoutWidth: root.width
    property ClockSidePanel panels: null
    property HealthAssistant assistant: null

    property string stateFilter: "new"
    property string sourceFilter: ""

    readonly property var groups: Array.from(HealthService.journal.groups ?? [])
    readonly property var noise: HealthService.journal.noise ?? ({})
    readonly property var shown: root.groups.filter(g => g.state === root.stateFilter
        && (root.sourceFilter === "" || (root.sourceFilter === "kernel" ? g.source === "kernel" : g.source !== "kernel")))
    readonly property int newCount: root.groups.filter(g => g.state === "new").length
    readonly property string openFp: root.panels?.open ? String(root.panels.current?.fp ?? "") : ""

    readonly property string pageSubtitle: Translation.tr("%1 new · %2 known")
        .arg(root.newCount).arg(root.noise.knownGroups ?? 0)

    function showFinding(id): void {
        const fp = String(id).replace(/^journal:/, "");
        const g = root.groups.find(x => x.fp === fp);
        if (!g)
            return;
        root.stateFilter = g.state;
        root.open(g);
    }

    function open(g): void {
        root.panels?.show(groupSheet, { fp: g.fp, assistant: root.assistant });
    }

    Component {
        id: groupSheet
        JournalGroupSheet {}
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

            // The noise figure.
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: noiseRow.implicitHeight + ClockStyle.gapLarge * 2
                radius: ClockStyle.radiusLarge
                color: ClockStyle.colPane

                RowLayout {
                    id: noiseRow
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: ClockStyle.cardPadding
                        rightMargin: ClockStyle.cardPadding
                    }
                    spacing: ClockStyle.gapLarge

                    StyledText {
                        text: String(root.noise.knownGroups ?? 0)
                        font.family: ClockStyle.fontMain
                        font.variableAxes: HealthStyle.axesThin
                        font.pixelSize: 60
                        color: ClockStyle.colSubtext
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            text: Translation.tr("Known noise, kept out of the way")
                            font.pixelSize: ClockStyle.textNormal + 1
                            font.weight: Font.DemiBold
                            color: ClockStyle.colOnSurface
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Error groups seen on %1 or more of the last %2 boots. They wrote %3 lines this boot and never alert.")
                                .arg(Config.options?.health?.noise?.knownAfterBoots ?? 3)
                                .arg(Config.options?.health?.noise?.ofLastBoots ?? 5)
                                .arg(root.noise.knownLines ?? 0)
                            wrapMode: Text.Wrap
                            font.pixelSize: ClockStyle.textSmall
                            color: ClockStyle.colSubtext
                        }
                    }
                }
            }

            // Only the user's own journal is readable: say so, and how to change it.
            Rectangle {
                Layout.fillWidth: true
                visible: HealthService.journalAccess === "user"
                implicitHeight: accessText.implicitHeight + ClockStyle.gapLarge * 2
                radius: ClockStyle.radiusLarge
                color: ClockStyle.colTertiaryContainer

                StyledText {
                    id: accessText
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        margins: ClockStyle.cardPadding
                    }
                    text: Translation.tr("Only your own programs' messages are readable. To see the system's too, join the systemd-journal group:") + "\nsudo usermod -aG systemd-journal $USER"
                    wrapMode: Text.Wrap
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colOnTertiaryContainer
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                Repeater {
                    model: [
                        { id: "new", label: Translation.tr("New") },
                        { id: "known", label: Translation.tr("Known") },
                        { id: "muted", label: Translation.tr("Muted") }
                    ]
                    ClockFormChip {
                        required property var modelData
                        readonly property int n: root.groups.filter(g => g.state === modelData.id).length
                        label: `${modelData.label} ${n}`
                        selected: root.stateFilter === modelData.id
                        onTriggered: root.stateFilter = modelData.id
                    }
                }

                Repeater {
                    model: [
                        { id: "kernel", label: Translation.tr("Kernel") },
                        { id: "programs", label: Translation.tr("Programs") }
                    ]
                    ClockFormChip {
                        required property var modelData
                        symbol: modelData.id === "kernel" ? "memory" : "apps"
                        label: modelData.label
                        selected: root.sourceFilter === modelData.id
                        onTriggered: root.sourceFilter = root.sourceFilter === modelData.id ? "" : modelData.id
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapTiny

                Repeater {
                    model: ScriptModel {
                        values: root.shown.slice(0, 150)
                        objectProp: "fp"
                    }

                    GroupRow {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        group: modelData
                        entranceIndex: index
                    }
                }
            }

            ClockEmptyState {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: ClockStyle.gapHuge
                visible: root.shown.length === 0 && HealthService.synced
                symbol: root.stateFilter === "new" ? "mark_email_read" : "inbox"
                shape: "Cookie7Sided"
                title: root.stateFilter === "new" ? Translation.tr("Nothing new since you last looked")
                    : root.stateFilter === "muted" ? Translation.tr("Nothing muted") : Translation.tr("No known noise yet")
                subtitle: root.stateFilter === "new" ? Translation.tr("A message the system never wrote before shows up here.") : ""
            }
        }
    }

    component GroupRow: Rectangle {
        id: row

        property var group: null
        property int entranceIndex: 0
        readonly property bool isNew: row.group?.state === "new"
        readonly property bool isOpen: root.openFp === row.group?.fp

        implicitHeight: Math.max(56, rowLayout.implicitHeight + ClockStyle.gap * 2)
        radius: ClockStyle.radiusNormal
        color: row.isOpen ? ClockStyle.colSecondaryContainer : rowHover.hovered ? ClockStyle.colRailRowHover : ClockStyle.colPane

        Behavior on color {
            animation: ClockStyle.motionFast.colorAnimation.createObject(this)
        }

        StaggeredEntrance {
            index: Math.min(row.entranceIndex, 12)
            active: !ClockStyle.reducedMotion
        }

        HoverHandler {
            id: rowHover
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            // The open row's second click closes its sheet.
            onClicked: row.isOpen ? root.panels.close() : root.open(row.group)
        }

        RowLayout {
            id: rowLayout
            anchors {
                fill: parent
                leftMargin: ClockStyle.gapLarge
                rightMargin: ClockStyle.gapLarge
            }
            spacing: ClockStyle.gap

            Rectangle {
                visible: !root.compact
                implicitWidth: srcText.implicitWidth + 14
                implicitHeight: srcText.implicitHeight + 6
                radius: 8
                color: ClockStyle.colRailRow

                StyledText {
                    id: srcText
                    anchors.centerIn: parent
                    text: HealthText.sourceLabel(row.group?.source).slice(0, 28)
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: ClockStyle.textSmall - 1
                    color: ClockStyle.colSubtext
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: row.group?.sample ?? row.group?.template ?? ""
                elide: Text.ElideRight
                font.family: Appearance.font.family.monospace
                font.pixelSize: ClockStyle.textSmall + 1
                color: ClockStyle.colOnSurface
            }

            StyledText {
                visible: !root.compact
                text: HealthText.journalSeen(row.group)
                font.pixelSize: ClockStyle.textSmall
                font.weight: Font.Bold
                color: row.isNew ? ClockStyle.colError : ClockStyle.colSubtext
            }

            HealthAnswerMark {
                Layout.alignment: Qt.AlignVCenter
                assistant: root.assistant
                key: row.group ? `journal:${row.group.fp}` : ""
                color: ClockStyle.colOnSurface
            }

            StyledText {
                Layout.minimumWidth: 44
                horizontalAlignment: Text.AlignRight
                text: String(row.group?.countBoot ?? 0)
                font.family: ClockStyle.fontMain
                font.variableAxes: ClockStyle.axesDigitsBold
                font.pixelSize: 26
                font.features: { "tnum": 1 }
                color: ClockStyle.colOnSurface
            }
        }
    }
}
