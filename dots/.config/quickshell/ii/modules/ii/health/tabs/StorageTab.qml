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
 * Hardware (still the "storage" tab inside): storage first — free space as the one
 * number per filesystem, a segmented bar that shows how much of the used part is yours
 * to take back, and each drive's SMART health with its wear on the M3E wavy ring, the
 * only ring in the app — then the rest of the machine (HealthHardwareSection).
 */
Item {
    id: root

    property double now: Date.now()
    property bool compact: false
    property real layoutWidth: root.width
    property ClockSidePanel panels: null
    property HealthAssistant assistant: null

    readonly property bool sideBySide: root.layoutWidth >= HealthStyle.sideBySideMin
    readonly property var filesystems: Array.from(HealthService.vitals?.fs ?? [])
    readonly property var drives: HealthService.drives
    readonly property var cleanupSizes: HealthService.system?.cleanup ?? ({})
    readonly property real reclaimable: Number(root.cleanupSizes.journal ?? 0) + Number(root.cleanupSizes.pacmanCache ?? 0) + Number(root.cleanupSizes.trash ?? 0)
    readonly property var orphans: Array.from(HealthService.system?.packages?.orphans ?? [])
    readonly property var rootFs: root.filesystems.find(f => f.mount === "/") ?? root.filesystems[0] ?? null

    readonly property string pageSubtitle: root.rootFs
        ? Translation.tr("%1 free on /").arg(HealthText.bytes(root.rootFs.avail))
        : ""

    // The FAB and the panes toggle: pressing what opened the sheet closes it.
    function primaryAction(): void {
        if (root.panels?.isShowing(cleanupSheet))
            root.panels.close();
        else
            root.panels?.show(cleanupSheet, {});
    }

    function showFinding(id): void {
        root.panels?.show(findingSheet, { findingId: id, assistant: root.assistant, onFreeSpace: () => root.primaryAction() });
    }

    function toggle(id): void {
        if (root.panels?.open && root.panels.current?.findingId === id)
            root.panels.close();
        else
            root.showFinding(id);
    }

    Component {
        id: cleanupSheet
        CleanupSheet {}
    }

    Component {
        id: findingSheet
        FindingSheet {}
    }

    StyledFlickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: grid.implicitHeight + ClockStyle.fabClearance
        clip: true

        GridLayout {
            id: grid
            width: flick.width
            columns: root.sideBySide ? 2 : 1
            columnSpacing: ClockStyle.paneGap
            rowSpacing: ClockStyle.paneGap

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 1
                spacing: ClockStyle.paneGap

                Repeater {
                    // A new list on every vitals tick: matched by mount, updated in place.
                    model: ScriptModel {
                        values: root.filesystems
                        objectProp: "mount"
                    }

                    FilesystemPane {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        fs: modelData
                        entranceIndex: index
                    }
                }

                CleanupPane {
                    Layout.fillWidth: true
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 1
                spacing: ClockStyle.paneGap

                Repeater {
                    model: ScriptModel {
                        values: root.drives
                        objectProp: "path"
                    }

                    DrivePane {
                        required property var modelData
                        Layout.fillWidth: true
                        drive: modelData
                    }
                }

                ClockEmptyState {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: ClockStyle.gapHuge
                    visible: root.drives.length === 0 && HealthService.synced
                    symbol: "storage"
                    shape: "Cookie9Sided"
                    shapeSize: ClockStyle.emptyShapeSmall
                    title: HealthService.sources?.drives === false ? Translation.tr("Drive health needs UDisks2") : Translation.tr("No drive reports its health")
                    subtitle: HealthService.sources?.drives === false ? Translation.tr("Install udisks2 to read SMART without root.") : ""
                }

                // Under the drives, in the column the drive card leaves half empty: the
                // first cards show without scrolling, which says there is more below.
                HealthHardwareSection {
                    id: hardware
                    Layout.fillWidth: true
                    layoutWidth: width
                    openFinding: id => root.toggle(id)
                }
            }
        }
    }

    component FilesystemPane: Rectangle {
        id: pane

        property var fs: null
        property int entranceIndex: 0
        readonly property var finding: HealthService.finding(`disk:${pane.fs?.mount ?? ""}`)
        readonly property real total: Math.max(1, Number(pane.fs?.total ?? 1))
        readonly property real free: Number(pane.fs?.avail ?? 0)
        readonly property real used: Math.max(0, pane.total - pane.free)
        readonly property real takeBack: pane.fs?.mount === root.rootFs?.mount ? Math.min(pane.used, root.reclaimable) : 0
        readonly property color colUsed: pane.finding ? (pane.finding.sev === "critical" ? ClockStyle.colError : ClockStyle.colTertiary) : ClockStyle.colPrimary

        implicitHeight: paneColumn.implicitHeight + ClockStyle.cardPadding * 2
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colPane

        StaggeredEntrance {
            index: pane.entranceIndex
            active: !ClockStyle.reducedMotion
        }

        MouseArea {
            anchors.fill: parent
            enabled: pane.finding !== null
            cursorShape: pane.finding ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.toggle(pane.finding.id)
        }

        ColumnLayout {
            id: paneColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: ClockStyle.cardPadding
            }
            spacing: ClockStyle.gapSmall

            RowLayout {
                Layout.fillWidth: true

                StyledText {
                    Layout.fillWidth: true
                    text: pane.fs?.mount ?? ""
                    elide: Text.ElideRight
                    font.family: ClockStyle.fontTitle
                    font.variableAxes: ClockStyle.axesTitle
                    font.pixelSize: ClockStyle.textLarge
                    color: ClockStyle.colOnSurface
                }
                StyledText {
                    text: `${pane.fs?.fstype ?? ""} · ${String(pane.fs?.device ?? "").replace("/dev/", "")}`
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colSubtext
                }
            }

            RowLayout {
                spacing: ClockStyle.gapSmall

                StyledText {
                    text: HealthText.bytes(pane.free).split(" ")[0]
                    font.family: ClockStyle.fontMain
                    font.variableAxes: ClockStyle.axesDigitsBold
                    font.pixelSize: 52
                    color: ClockStyle.colOnSurface
                }
                StyledText {
                    Layout.alignment: Qt.AlignBaseline
                    text: Translation.tr("%1 free of %2").arg(HealthText.bytes(pane.free).split(" ")[1] ?? "").arg(HealthText.bytes(pane.total))
                    font.pixelSize: ClockStyle.textNormal
                    color: ClockStyle.colSubtext
                }
            }

            // Used, the part of it that is yours to take back, and free.
            Row {
                id: seg
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                spacing: 3

                readonly property real usable: seg.width - seg.spacing * 2
                readonly property real wUsed: Math.max(6, (pane.used - pane.takeBack) / pane.total * seg.usable)
                readonly property real wBack: pane.takeBack > 0 ? Math.max(6, pane.takeBack / pane.total * seg.usable) : 0
                readonly property real wFree: Math.max(6, seg.usable - seg.wUsed - seg.wBack)

                Rectangle {
                    width: seg.wUsed
                    height: seg.height
                    color: pane.colUsed
                    topLeftRadius: 13
                    bottomLeftRadius: 13
                    topRightRadius: 6
                    bottomRightRadius: 6

                    Behavior on width {
                        animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                    }
                }
                Rectangle {
                    visible: seg.wBack > 0
                    width: seg.wBack
                    height: seg.height
                    radius: 6
                    color: ClockStyle.colTertiary
                }
                Rectangle {
                    width: seg.wFree
                    height: seg.height
                    color: ClockStyle.colField
                    topRightRadius: 13
                    bottomRightRadius: 13
                    topLeftRadius: 6
                    bottomLeftRadius: 6
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: ClockStyle.gapLarge

                Repeater {
                    model: [
                        { col: pane.colUsed, label: Translation.tr("Used %1").arg(HealthText.bytes(pane.used - pane.takeBack)) },
                        { col: ClockStyle.colTertiary, label: Translation.tr("Logs, caches and trash %1").arg(HealthText.bytes(pane.takeBack)), hide: pane.takeBack <= 0 },
                        { col: ClockStyle.colField, label: Translation.tr("Free %1").arg(HealthText.bytes(pane.free)) }
                    ]
                    Row {
                        required property var modelData
                        visible: !modelData.hide
                        spacing: 6
                        Rectangle {
                            width: 10
                            height: 10
                            radius: 3
                            anchors.verticalCenter: parent.verticalCenter
                            color: modelData.col
                        }
                        StyledText {
                            text: modelData.label
                            font.pixelSize: ClockStyle.textSmall
                            color: ClockStyle.colSubtext
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: pane.fs?.etaDays !== null && pane.fs?.etaDays !== undefined
                text: Translation.tr("At the last day's rate it fills in about %1 days.").arg(Math.max(1, Math.round(Number(pane.fs?.etaDays ?? 0))))
                wrapMode: Text.Wrap
                font.pixelSize: ClockStyle.textSmall
                color: pane.finding ? ClockStyle.colError : ClockStyle.colSubtext
            }
        }
    }

    component CleanupPane: Rectangle {
        implicitHeight: cleanColumn.implicitHeight + ClockStyle.cardPadding * 2
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colPane

        ColumnLayout {
            id: cleanColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: ClockStyle.cardPadding
            }
            spacing: ClockStyle.gapSmall

            StyledText {
                text: Translation.tr("Space you can take back")
                font.pixelSize: ClockStyle.textSmall
                font.weight: Font.Black
                font.letterSpacing: 1.0
                font.capitalization: Font.AllUppercase
                color: ClockStyle.colSubtext
            }

            Repeater {
                model: [
                    { label: Translation.tr("Journal archives"), detail: Translation.tr("Older than 4 weeks can go"), size: HealthText.bytes(root.cleanupSizes.journal) },
                    { label: Translation.tr("Package cache"), detail: Translation.tr("Keeps 2 versions of each package"), size: HealthText.bytes(root.cleanupSizes.pacmanCache), hide: HealthService.packageManager !== "pacman" },
                    { label: Translation.tr("Crash dumps"), detail: Translation.tr("systemd removes them after 3 days"), size: HealthText.bytes(root.cleanupSizes.coredumps) },
                    { label: Translation.tr("Trash"), detail: Translation.tr("Files you deleted"), size: HealthText.bytes(root.cleanupSizes.trash) }
                ]
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: cleanColumn.width
                    visible: !modelData.hide
                    spacing: ClockStyle.gap

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            text: modelData.label
                            font.pixelSize: ClockStyle.textNormal
                            font.weight: Font.DemiBold
                            color: ClockStyle.colOnSurface
                        }
                        StyledText {
                            text: modelData.detail
                            font.pixelSize: ClockStyle.textSmall
                            color: ClockStyle.colSubtext
                        }
                    }
                    StyledText {
                        text: modelData.size
                        font.family: ClockStyle.fontMain
                        font.variableAxes: ({ "wght": 700, "wdth": 45, "ROND": 100 })
                        font.pixelSize: 22
                        color: ClockStyle.colOnSurface
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.orphans.length > 0
                spacing: ClockStyle.gap

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        text: HealthText.plural(root.orphans.length, Translation.tr("%1 unused package"), Translation.tr("%1 unused packages"))
                        font.pixelSize: ClockStyle.textNormal
                        font.weight: Font.DemiBold
                        color: ClockStyle.colOnSurface
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.orphans.slice(0, 4).join(", ") + (root.orphans.length > 4 ? "…" : "")
                        elide: Text.ElideRight
                        font.pixelSize: ClockStyle.textSmall
                        color: ClockStyle.colSubtext
                    }
                }
                ClockButton {
                    label: Translation.tr("Review")
                    symbol: "terminal"
                    onClicked: HealthService.runInTerminal(["bash", "-c", "pacman -Qdt; echo; sudo pacman -Rns $(pacman -Qdtq)"])
                }
            }
        }
    }

    component DrivePane: Rectangle {
        id: dp

        property var drive: null
        readonly property var finding: HealthService.finding(`drive:${dp.drive?.id ?? ""}`)
        readonly property real wear: Number(dp.drive?.percentUsed ?? 0)
        property string selftestError: ""

        implicitHeight: driveColumn.implicitHeight + ClockStyle.cardPadding * 2
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colPane

        ColumnLayout {
            id: driveColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: ClockStyle.cardPadding
            }
            spacing: ClockStyle.gap

            ColumnLayout {
                spacing: 0
                StyledText {
                    text: dp.drive?.model ?? ""
                    font.family: ClockStyle.fontTitle
                    font.variableAxes: ClockStyle.axesTitle
                    font.pixelSize: ClockStyle.textLarge
                    color: ClockStyle.colOnSurface
                }
                StyledText {
                    text: [String(dp.drive?.kind ?? "").toUpperCase(), HealthText.bytes(dp.drive?.size), Translation.tr("read from UDisks, no root")].join(" · ")
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colSubtext
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapLarge

                Item {
                    implicitWidth: 128
                    implicitHeight: 128

                    ClockProgressRing {
                        anchors.fill: parent
                        value: Math.max(0.03, dp.wear / 100)
                        thickness: 10
                        wavy: true
                        colIndicator: dp.finding ? ClockStyle.colError : ClockStyle.colPrimary
                        colTrack: ClockStyle.colField
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: -2
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: dp.drive?.percentUsed !== null && dp.drive?.percentUsed !== undefined ? `${dp.drive.percentUsed} %` : "—"
                            font.family: ClockStyle.fontMain
                            font.variableAxes: ClockStyle.axesDigitsBold
                            font.pixelSize: 30
                            color: ClockStyle.colOnSurface
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Translation.tr("life used")
                            font.pixelSize: ClockStyle.textSmall - 1
                            color: ClockStyle.colSubtext
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: dp.finding ? HealthText.driveProblems(dp.finding.data).join(", ")
                        : dp.drive?.powerOnHours > 0 && dp.wear > 0
                            ? Translation.tr("Healthy. Wear has grown about 1 % per %1 powered-on hours.").arg(Math.round(dp.drive.powerOnHours / dp.wear))
                            : Translation.tr("Healthy.")
                    wrapMode: Text.Wrap
                    font.pixelSize: ClockStyle.textNormal + 1
                    color: dp.finding ? ClockStyle.colError : ClockStyle.colOnSurface
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 6
                rowSpacing: 6

                Repeater {
                    model: [
                        [Translation.tr("Temperature"), dp.drive?.tempC !== null && dp.drive?.tempC !== undefined ? `${Math.round(dp.drive.tempC)} °C` : "—"],
                        [Translation.tr("Spare blocks"), dp.drive?.availSpare !== null && dp.drive?.availSpare !== undefined ? `${dp.drive.availSpare} %` : "—"],
                        [Translation.tr("Powered on"), dp.drive?.powerOnHours ? Translation.tr("%1 h").arg(dp.drive.powerOnHours) : "—"],
                        [Translation.tr("Written"), dp.drive?.dataWritten ? HealthText.terabytes(dp.drive.dataWritten) : "—"],
                        [Translation.tr("Media errors"), String(dp.drive?.mediaErrors ?? "—")],
                        [Translation.tr("Unsafe shutdowns"), String(dp.drive?.unsafeShutdowns ?? "—")]
                    ]

                    Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: kv.implicitHeight + 14
                        radius: ClockStyle.radiusSmall
                        color: ClockStyle.colRailRow

                        ColumnLayout {
                            id: kv
                            anchors {
                                left: parent.left
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: 10
                                rightMargin: 10
                            }
                            spacing: 0
                            StyledText {
                                text: modelData[0]
                                font.pixelSize: ClockStyle.textSmall - 2
                                font.weight: Font.Black
                                font.capitalization: Font.AllUppercase
                                color: ClockStyle.colSubtext
                            }
                            StyledText {
                                text: modelData[1]
                                font.pixelSize: ClockStyle.textNormal
                                font.weight: Font.Bold
                                font.features: { "tnum": 1 }
                                color: ClockStyle.colOnSurface
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true

                StyledText {
                    Layout.fillWidth: true
                    text: Number(dp.drive?.selftestPct ?? -1) >= 0
                        ? Translation.tr("Self-test running · %1 % left").arg(dp.drive.selftestPct)
                        : dp.selftestError.length > 0 ? dp.selftestError
                        : Translation.tr("Last self-test: %1").arg(dp.drive?.selftest ?? "—")
                    wrapMode: Text.Wrap
                    font.pixelSize: ClockStyle.textSmall
                    color: dp.selftestError.length > 0 ? ClockStyle.colError : ClockStyle.colSubtext
                }
                ClockButton {
                    label: Translation.tr("Run a self-test")
                    symbol: "fact_check"
                    enabled: Number(dp.drive?.selftestPct ?? -1) < 0
                    onClicked: {
                        dp.selftestError = "";
                        HealthService.act("selftest", { drive: dp.drive.path }, (ok, data, error) => {
                            if (!ok)
                                dp.selftestError = Translation.tr("The self-test did not start (%1)").arg(error || "?");
                        });
                    }
                }
            }
        }
    }
}
