import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components

/**
 * The stopwatch panel: the time with its hundredths, the three controls, and
 * the laps — fastest on the primary container, slowest on the error container,
 * as in the Clock app.
 */
ColumnLayout {
    id: panel

    property var host: null

    readonly property bool running: TimerService.stopwatchRunning
    readonly property int centiseconds: TimerService.stopwatchTime
    readonly property bool started: panel.running || panel.centiseconds > 0
    readonly property var laps: TimerService.stopwatchLaps ?? []
    readonly property var lapDurations: panel.laps.map((total, i) => total - (i > 0 ? panel.laps[i - 1] : 0))
    readonly property int fastest: panel.lapDurations.length > 1 ? panel.lapDurations.indexOf(Math.min(...panel.lapDurations)) : -1
    readonly property int slowest: panel.lapDurations.length > 1 ? panel.lapDurations.indexOf(Math.max(...panel.lapDurations)) : -1
    readonly property var time: ClockFormat.stopwatch(panel.centiseconds)

    spacing: 8

    // ── Time: the main digits and the hundredths on one baseline ───────
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 116
        radius: ClockStyle.radiusLarge
        color: panel.running ? ClockStyle.colPrimaryContainer : ClockStyle.colField
        Behavior on color {
            animation: ClockStyle.motionFast.colorAnimation.createObject(this)
        }

        RowLayout {
            anchors.centerIn: parent
            spacing: 2
            StyledText {
                Layout.alignment: Qt.AlignBaseline
                text: panel.time.main
                color: panel.running ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurface
                font.family: ClockStyle.fontMain
                font.variableAxes: ClockStyle.axesDigitsBold
                font.pixelSize: 68
            }
            StyledText {
                Layout.alignment: Qt.AlignBaseline
                text: "." + panel.time.fraction
                color: panel.running ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurfaceVariant
                opacity: 0.7
                font.family: ClockStyle.fontMain
                font.variableAxes: ClockStyle.axesDigits
                font.pixelSize: 32
            }
        }
    }

    // ── Controls: reset · play · lap, play exactly centred ─────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        ClockButton {
            Layout.fillWidth: true
            Layout.preferredWidth: 2
            symbol: "restart_alt"
            label: Translation.tr("Reset")
            enabled: panel.started && !panel.running
            onClicked: TimerService.stopwatchReset()
        }
        ClockPlayButton {
            Layout.alignment: Qt.AlignVCenter
            size: 56
            running: panel.running
            onClicked: TimerService.toggleStopwatch()
        }
        ClockButton {
            Layout.fillWidth: true
            Layout.preferredWidth: 2
            symbol: "flag"
            label: Translation.tr("Lap")
            enabled: panel.running
            onClicked: TimerService.stopwatchRecordLap()
        }
    }

    // ── Laps, newest first ──────────────────────────────────────────────
    StyledText {
        Layout.topMargin: 4
        Layout.leftMargin: 4
        visible: panel.laps.length > 0
        text: Translation.tr("Laps")
        color: ClockStyle.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.Bold
    }

    ListView {
        id: lapList
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, 40 * 5 + spacing * 4)
        visible: panel.laps.length > 0
        clip: true
        spacing: 3
        boundsBehavior: Flickable.StopAtBounds
        model: panel.laps.length
        delegate: Rectangle {
            id: lapRow
            required property int index
            readonly property int lapIndex: panel.laps.length - 1 - lapRow.index
            readonly property bool isFastest: lapRow.lapIndex === panel.fastest
            readonly property bool isSlowest: lapRow.lapIndex === panel.slowest
            readonly property color colContent: lapRow.isFastest ? ClockStyle.colOnPrimaryContainer
                : lapRow.isSlowest ? ClockStyle.colOnErrorContainer
                : ClockStyle.colOnSurface
            width: ListView.view.width
            height: 40
            radius: lapRow.index === 0 ? ClockStyle.radiusNormal : ClockStyle.radiusSmall
            color: lapRow.isFastest ? ClockStyle.colPrimaryContainer
                : lapRow.isSlowest ? ClockStyle.colErrorContainer
                : ClockStyle.colField

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 8
                StyledText {
                    text: Translation.tr("Lap %1").arg(lapRow.lapIndex + 1)
                    color: lapRow.colContent
                    font.pixelSize: ClockStyle.textNormal
                    font.weight: Font.DemiBold
                }
                MaterialSymbol {
                    visible: lapRow.isFastest || lapRow.isSlowest
                    text: lapRow.isFastest ? "bolt" : "hourglass_bottom"
                    iconSize: 16
                    fill: 1
                    color: lapRow.colContent
                }
                Item { Layout.fillWidth: true }
                StyledText {
                    text: ClockFormat.stopwatch(panel.lapDurations[lapRow.lapIndex] ?? 0).main
                        + "." + ClockFormat.stopwatch(panel.lapDurations[lapRow.lapIndex] ?? 0).fraction
                    color: lapRow.colContent
                    font.family: ClockStyle.fontMain
                    font.variableAxes: ClockStyle.axesDigitsBold
                    font.pixelSize: 20
                }
                StyledText {
                    text: ClockFormat.stopwatch(panel.laps[lapRow.lapIndex] ?? 0).main
                    color: lapRow.colContent
                    opacity: 0.7
                    font.pixelSize: ClockStyle.textSmall
                }
            }
        }
    }
}
