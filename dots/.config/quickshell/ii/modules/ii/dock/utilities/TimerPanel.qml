import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components

/**
 * The timer panel: every countdown as a row with its own ring, and a quick
 * start — the preset chips and a minutes stepper — under them.
 */
ColumnLayout {
    id: panel

    property var host: null
    property int customMinutes: 15

    readonly property int tick: TimerService.countdownTick
    readonly property var countdowns: TimerService.countdowns ?? []
    readonly property var presets: Config.options?.dock?.utilities?.timer?.presets ?? [1, 5, 10, 25]

    spacing: 8

    // ── Countdowns ──────────────────────────────────────────────────────
    Repeater {
        model: panel.countdowns
        delegate: Rectangle {
            id: row
            required property var modelData
            readonly property bool finished: row.modelData.notified === true
            readonly property bool paused: row.modelData.paused === true
            readonly property int secondsLeft: { panel.tick; return TimerService.countdownSecondsLeft(row.modelData); }
            readonly property color colContent: row.finished ? ClockStyle.colOnErrorContainer
                : row.paused ? ClockStyle.colOnSurface : ClockStyle.colOnPrimaryContainer
            Layout.fillWidth: true
            implicitHeight: 72
            radius: ClockStyle.radiusLarge
            color: row.finished ? ClockStyle.colErrorContainer
                : row.paused ? ClockStyle.colField : ClockStyle.colPrimaryContainer

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 10

                Item {
                    implicitWidth: 52
                    implicitHeight: 52
                    ClockProgressRing {
                        anchors.fill: parent
                        value: row.finished ? 0 : row.secondsLeft / Math.max(1, row.modelData.durationSeconds ?? 1)
                        thickness: 5
                        wavy: !row.paused && !row.finished
                        waves: 8
                        tickDuration: 1000
                        colIndicator: row.finished ? ClockStyle.colError : ClockStyle.colPrimary
                        colTrack: ColorUtils.applyAlpha(row.colContent, 0.16)
                    }
                    ClockPlayButton {
                        anchors.centerIn: parent
                        size: 34
                        visible: !row.finished
                        running: !row.paused
                        onClicked: TimerService.toggleCountdown(row.modelData.id)
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: row.finished
                        text: "alarm"
                        iconSize: 22
                        fill: 1
                        color: row.colContent
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: row.finished ? Translation.tr("Done") : TimerService.formatCountdownDuration(row.secondsLeft)
                        color: row.colContent
                        font.family: ClockStyle.fontMain
                        font.variableAxes: ClockStyle.axesDigitsBold
                        font.pixelSize: 28
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: String(row.modelData.label ?? "")
                        color: row.colContent
                        opacity: 0.8
                        font.pixelSize: ClockStyle.textSmall
                        elide: Text.ElideRight
                    }
                }

                ClockCardAction {
                    visible: !row.finished
                    symbol: "more_time"
                    tip: Translation.tr("Add 1 minute")
                    colContent: row.colContent
                    onClicked: TimerService.extendCountdown(row.modelData.id, 60)
                }
                ClockCardAction {
                    symbol: row.finished ? "check" : "close"
                    tip: row.finished ? Translation.tr("Dismiss") : Translation.tr("Cancel timer")
                    colContent: row.colContent
                    onClicked: TimerService.removeCountdown(row.modelData.id)
                }
            }
        }
    }

    // ── Quick start ─────────────────────────────────────────────────────
    StyledText {
        Layout.topMargin: panel.countdowns.length > 0 ? 6 : 0
        Layout.leftMargin: 4
        text: Translation.tr("Quick start")
        color: ClockStyle.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.Bold
    }

    // The presets as one row of equal pills: minutes in condensed digits.
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: panel.presets.slice(0, 4)
            delegate: RippleButton {
                id: preset
                required property int modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: 56
                buttonRadius: height / 2
                buttonRadiusPressed: ClockStyle.radiusNormal
                colBackground: ClockStyle.colSecondaryContainer
                colBackgroundHover: ClockStyle.colSecondaryContainerHover
                colRipple: ClockStyle.colSecondaryContainerActive
                onClicked: TimerService.addCountdown(preset.modelData)
                contentItem: Item {
                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 2
                        StyledText {
                            Layout.alignment: Qt.AlignBaseline
                            text: String(preset.modelData)
                            color: ClockStyle.colOnSecondaryContainer
                            font.family: ClockStyle.fontMain
                            font.variableAxes: ClockStyle.axesDigitsBold
                            font.pixelSize: 26
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignBaseline
                            text: Translation.tr("min")
                            color: ClockStyle.colOnSecondaryContainer
                            opacity: 0.75
                            font.pixelSize: ClockStyle.textSmall
                            font.weight: Font.Bold
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 60
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colField

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 8
            spacing: 8

            ClockStepper {
                Layout.fillWidth: true
                value: panel.customMinutes
                from: 1
                to: 600
                format: value => Translation.tr("%1 min").arg(value)
                onMoved: value => panel.customMinutes = value
            }
            ClockButton {
                variant: "filled"
                symbol: "play_arrow"
                label: Translation.tr("Start")
                onClicked: TimerService.addCountdown(panel.customMinutes)
            }
        }
    }
}
