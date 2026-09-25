import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * A running, paused or finished timer: a wavy ring that empties as time passes, the
 * time left inside it, and Android's +1:00, pause and reset around it.
 */
Rectangle {
    id: root

    required property var countdown

    // ── Tokens ──────────────────────────────────────────────────────────
    readonly property real ringSize: Math.min(root.width - ClockStyle.cardPadding * 2, ClockStyle.timerCardMinWidth * 0.82)
    readonly property real ringThickness: Math.max(ClockStyle.gapSmall - 2, root.ringSize * 0.045)
    readonly property real timeSize: root.ringSize * (root.secondsLeft >= 3600 ? 0.2 : 0.26)
    readonly property color colCard: root.finished ? ClockStyle.colErrorContainer : ClockStyle.colSurfaceHigh
    readonly property color colContent: root.finished ? ClockStyle.colOnErrorContainer : ClockStyle.colOnSurface
    readonly property color colRing: root.finished ? ClockStyle.colError : root.paused ? ClockStyle.colOutline : ClockStyle.colPrimary
    readonly property color colTrack: root.finished ? ClockStyle.colErrorContainerHover : ClockStyle.colSecondaryContainer

    readonly property string countdownId: String(root.countdown?.id ?? "")
    readonly property bool finished: Boolean(root.countdown?.notified)
    readonly property bool paused: Boolean(root.countdown?.paused)
    readonly property int secondsLeft: {
        TimerService.countdownTick;
        return TimerService.countdownSecondsLeft(root.countdown);
    }
    readonly property real progress: {
        TimerService.countdownTick;
        return 1 - TimerService.countdownProgress(root.countdown);
    }

    signal renameRequested()

    implicitHeight: cardColumn.implicitHeight + ClockStyle.cardPadding * 2
    radius: ClockStyle.radiusCard
    color: root.colCard

    Behavior on color {
        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
    }

    ColumnLayout {
        id: cardColumn
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: ClockStyle.cardPadding
        }
        spacing: ClockStyle.gap

        RowLayout {
            Layout.fillWidth: true
            spacing: ClockStyle.gapSmall

            RippleButton {
                Layout.fillWidth: true
                implicitHeight: ClockStyle.iconButton
                buttonRadius: ClockStyle.radiusNormal
                colBackground: "transparent"
                colBackgroundHover: ClockStyle.colSurfaceHover
                onClicked: root.renameRequested()

                contentItem: RowLayout {
                    spacing: ClockStyle.gapSmall

                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: ClockStyle.gapSmall
                        text: String(root.countdown?.label ?? Translation.tr("Timer"))
                        elide: Text.ElideRight
                        font.pixelSize: ClockStyle.textNormal
                        font.weight: Font.DemiBold
                        color: root.colContent
                    }

                    MaterialSymbol {
                        text: "edit"
                        iconSize: ClockStyle.iconSmall
                        color: root.colContent
                        opacity: 0.6
                    }
                }
            }

            ClockIconButton {
                symbol: "close"
                tooltip: Translation.tr("Delete")
                colIcon: root.colContent
                onClicked: TimerService.removeCountdown(root.countdownId)
            }
        }

        Item {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: root.ringSize
            implicitHeight: root.ringSize

            ClockProgressRing {
                anchors.fill: parent
                value: root.finished ? 1 : root.progress
                thickness: root.ringThickness
                wavy: !root.paused && !root.finished
                colIndicator: root.colRing
                colTrack: root.colTrack
            }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 0

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.finished ? Translation.tr("Time's up") : ClockFormat.duration(root.secondsLeft)
                    font.family: ClockStyle.fontMain
                    font.variableAxes: ClockStyle.axesDigitsBold
                    font.pixelSize: root.finished ? root.timeSize * 0.62 : root.timeSize
                    color: root.colContent
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.paused ? Translation.tr("Paused") : ClockFormat.shortDuration(root.countdown?.durationSeconds ?? 0)
                    font.pixelSize: ClockStyle.textSmall
                    color: root.colContent
                    opacity: 0.7
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: ClockStyle.gap

            ClockButton {
                variant: "tonal"
                label: "+1:00"
                onClicked: TimerService.extendCountdown(root.countdownId, 60)
            }

            ClockPlayButton {
                size: ClockStyle.fabSize
                running: !root.paused && !root.finished
                onClicked: {
                    if (root.finished)
                        TimerService.restartCountdown(root.countdownId);
                    else
                        TimerService.toggleCountdown(root.countdownId);
                }
            }

            ClockIconButton {
                symbol: "restart_alt"
                tooltip: Translation.tr("Reset")
                colBackground: ClockStyle.colSurfaceHighest
                colIcon: ClockStyle.colOnSurfaceVariant
                size: ClockStyle.buttonHeight
                onClicked: {
                    TimerService.restartCountdown(root.countdownId);
                    TimerService.pauseCountdown(root.countdownId);
                }
            }
        }
    }
}
