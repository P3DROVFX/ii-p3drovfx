pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.modes

/**
 * One tracked command run (services/modes/ModeTasks.qml) as a side sheet of the
 * Activity tab: how it went, the per-item lines of its ::ii-report, and what it
 * printed — live while it runs, with Stop; afterwards with Run again and Open log.
 */
ClockSheet {
    id: root

    property string runId: ""

    readonly property var run: {
        Modes.tasks.revision;
        return Modes.tasks.runById(root.runId);
    }
    readonly property bool running: root.run?.state === "running"
    readonly property var report: root.run?.report ?? null
    readonly property var details: Array.from(root.report?.details ?? [])
    readonly property var notes: Array.from(root.report?.notes ?? [])
    readonly property var owner: root.run ? (root.run.kind === "routine" ? Modes.routineById(root.run.owner) : Modes.modeById(root.run.owner)) : null
    readonly property string logPath: root.run ? `${root.run.dir}/output.log` : ""

    // Ticks the running time and reloads the log while the command is going.
    property real now: Date.now()
    Timer {
        running: root.running
        repeat: true
        interval: 2000
        onTriggered: {
            root.now = Date.now();
            logFile.reload();
        }
    }

    title: root.run?.label ?? Translation.tr("Run")
    subtitle: {
        if (!root.run)
            return Translation.tr("This run is no longer kept");
        const started = new Date(root.run.startedAt).toLocaleString(Qt.locale(), "dd/MM hh:mm");
        const span = (root.running ? root.now : root.run.endedAt) - root.run.startedAt;
        return root.running ? Translation.tr("Started %1 · running for %2").arg(started).arg(ModeUi.durationText(span / 1000))
            : Translation.tr("Started %1 · took %2").arg(started).arg(ModeUi.durationText(span / 1000));
    }

    FileView {
        id: logFile
        path: root.logPath
        printErrors: false
    }

    // What the log shows: no colour codes, no report lines (they are shown
    // above), the last 400 lines.
    readonly property string logText: {
        const raw = logFile.text() ?? "";
        const lines = raw.replace(/\x1b\[[0-9;]*[A-Za-z]/g, "").split("\n")
            .filter(l => !l.startsWith("::ii-report "));
        while (lines.length && !lines[lines.length - 1].trim().length)
            lines.pop();
        const cut = lines.length > 400 ? lines.length - 400 : 0;
        return (cut ? Translation.tr("… %1 earlier lines in the log file\n").arg(cut) : "") + lines.slice(cut).join("\n");
    }

    // ── Status ───────────────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        visible: root.run !== null
        implicitHeight: statusCol.implicitHeight + ClockStyle.gap * 2
        radius: ClockStyle.radiusLarge
        color: ModeUi.statusContainer(root.run?.state ?? "")

        ColumnLayout {
            id: statusCol
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: ClockStyle.gap
            }
            spacing: ClockStyle.gapTiny

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                MaterialSymbol {
                    text: ModeUi.statusIcon(root.run?.state ?? "")
                    iconSize: ClockStyle.iconSmall + 4
                    fill: 1
                    color: ModeUi.statusOnContainer(root.run?.state ?? "")
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.running ? Translation.tr("Running…") : Modes.tasks.titleOf(root.run ?? {})
                    wrapMode: Text.WordWrap
                    font.pixelSize: ClockStyle.textNormal + 1
                    font.weight: Font.DemiBold
                    color: ModeUi.statusOnContainer(root.run?.state ?? "")
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: text.length > 0
                text: {
                    if (root.running)
                        return Translation.tr("The result shows up here and in a notification when it finishes.");
                    const parts = [];
                    if (root.report?.summary)
                        parts.push(String(root.report.summary));
                    if (root.run?.lost)
                        parts.push(Translation.tr("It stopped without an exit status: the computer was shut down, or the process was killed."));
                    else if (root.run && root.run.exitCode !== null && root.run.exitCode !== undefined)
                        parts.push(Translation.tr("Exit status %1").arg(root.run.exitCode));
                    return parts.join("\n");
                }
                wrapMode: Text.WordWrap
                font.pixelSize: ClockStyle.textSmall
                color: ModeUi.statusOnContainer(root.run?.state ?? "")
            }
        }
    }

    // ── Report lines ─────────────────────────────────────────────────────
    Repeater {
        model: root.details

        delegate: Rectangle {
            id: detailRow
            required property var modelData
            required property int index
            readonly property string status: String(detailRow.modelData?.status ?? "")

            Layout.fillWidth: true
            implicitHeight: detailCol.implicitHeight + ClockStyle.gap * 2
            topLeftRadius: detailRow.index === 0 ? ClockStyle.radiusLarge : ClockStyle.radiusSmall / 2
            topRightRadius: topLeftRadius
            bottomLeftRadius: detailRow.index === root.details.length - 1 ? ClockStyle.radiusLarge : ClockStyle.radiusSmall / 2
            bottomRightRadius: bottomLeftRadius
            color: ClockStyle.colPane

            RowLayout {
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    margins: ClockStyle.gap
                }
                spacing: ClockStyle.gapSmall

                MaterialSymbol {
                    Layout.alignment: Qt.AlignTop
                    text: ModeUi.statusIcon(detailRow.status)
                    iconSize: ClockStyle.iconSmall + 2
                    color: detailRow.status === "error" ? ClockStyle.colError
                        : detailRow.status === "warn" ? ClockStyle.colTertiary : ClockStyle.colPrimary
                }

                ColumnLayout {
                    id: detailCol
                    Layout.fillWidth: true
                    spacing: 1

                    StyledText {
                        Layout.fillWidth: true
                        text: String(detailRow.modelData?.label ?? "")
                        elide: Text.ElideMiddle
                        font.pixelSize: ClockStyle.textSmall
                        font.weight: Font.DemiBold
                        color: ClockStyle.colOnSurface
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: String(detailRow.modelData?.value ?? "")
                        wrapMode: Text.WordWrap
                        font.pixelSize: ClockStyle.textSmall
                        color: ClockStyle.colOnSurfaceVariant
                    }
                }
            }
        }
    }

    Repeater {
        model: root.notes

        delegate: StyledText {
            required property var modelData
            Layout.fillWidth: true
            text: "• " + String(modelData)
            wrapMode: Text.WrapAnywhere
            font.pixelSize: ClockStyle.textSmall
            color: ClockStyle.colError
        }
    }

    // ── Output ───────────────────────────────────────────────────────────
    StyledText {
        Layout.fillWidth: true
        Layout.topMargin: ClockStyle.gapTiny
        visible: root.run !== null
        text: Translation.tr("Output")
        font.pixelSize: ClockStyle.textSmall
        font.weight: Font.DemiBold
        color: ClockStyle.colSubtext
    }

    Rectangle {
        Layout.fillWidth: true
        visible: root.run !== null
        implicitHeight: logEdit.implicitHeight + ClockStyle.gap * 2
        radius: ClockStyle.radiusSmall
        color: ClockStyle.colPane

        TextEdit {
            id: logEdit
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: ClockStyle.gap
            }
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.WrapAnywhere
            textFormat: TextEdit.PlainText
            text: root.logText.length ? root.logText : (root.running ? Translation.tr("Waiting for output…") : Translation.tr("No output"))
            font.family: Appearance.font.family.monospace
            font.pixelSize: ClockStyle.textSmall - 1
            color: ClockStyle.colOnSurfaceVariant
            selectionColor: ClockStyle.colPrimaryContainer
            selectedTextColor: ClockStyle.colOnPrimaryContainer
        }
    }

    actions: [
        ClockSheetAction {
            visible: root.running
            danger: true
            symbol: "stop_circle"
            label: Translation.tr("Stop")
            onClicked: Modes.tasks.stop(root.runId)
        },
        ClockSheetAction {
            visible: !root.running && root.run !== null
            symbol: "description"
            label: Translation.tr("Open log file")
            onClicked: Quickshell.execDetached(["xdg-open", root.logPath])
        },
        ClockSheetAction {
            visible: !root.running && root.run?.kind === "routine" && root.owner !== null
            primary: true
            symbol: "replay"
            label: Translation.tr("Run again")
            onClicked: {
                Modes.runRoutine(root.run.owner, "manual");
                root.close();
            }
        }
    ]
}
