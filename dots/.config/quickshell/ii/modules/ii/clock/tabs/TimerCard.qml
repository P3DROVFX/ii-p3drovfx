import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * A running, paused or finished timer, laid out across the card: the wavy ring on the
 * left draining continuously, the time left in large digits beside it, and a row of
 * three equal-height controls under it — +1:00, start/pause and reset — with start/pause
 * exactly in the middle.
 *
 * The ring glides over each second instead of stepping, and pausing flattens its wave
 * rather than swapping it for a different ring. Rename and delete reveal on hover like
 * the dashboard's to-do rows.
 */
Rectangle {
    id: root

    required property var countdown
    property real layoutWidth: root.width

    // ── Tokens ──────────────────────────────────────────────────────────
    readonly property real cardHeight: 212
    readonly property real ringSize: Math.round(Math.min(root.cardHeight - ClockStyle.cardPadding * 2, root.layoutWidth * 0.36))
    readonly property real ringThickness: Math.max(8, root.ringSize * 0.06)
    readonly property real controlHeight: 52
    readonly property real timeSize: Math.round(Math.min(64, (root.layoutWidth - root.ringSize - ClockStyle.cardPadding * 3) / (root.secondsLeft >= 3600 ? 4.6 : 3.2)))
    readonly property color colCard: root.finished ? ClockStyle.colErrorContainer : ClockStyle.colIdleCard
    readonly property color colContent: root.finished ? ClockStyle.colOnErrorContainer : ClockStyle.colOnSurface
    readonly property color colRing: root.finished ? ClockStyle.colError : root.paused ? ClockStyle.colOutline : ClockStyle.colPrimary
    readonly property color colTrack: root.finished ? ClockStyle.colErrorContainerHover : ClockStyle.colSecondaryContainer

    readonly property string countdownId: String(root.countdown?.id ?? "")
    readonly property bool finished: Boolean(root.countdown?.notified)
    readonly property bool paused: Boolean(root.countdown?.paused)
    readonly property bool running: !root.paused && !root.finished
    readonly property int secondsLeft: {
        TimerService.countdownTick;
        return TimerService.countdownSecondsLeft(root.countdown);
    }
    readonly property real progress: {
        TimerService.countdownTick;
        return 1 - TimerService.countdownProgress(root.countdown);
    }
    readonly property bool engaged: cardHover.hovered || renameButton.activeFocus || deleteButton.activeFocus

    signal renameRequested()

    implicitHeight: root.cardHeight
    radius: ClockStyle.radiusCard
    color: root.colCard

    Behavior on color {
        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
    }

    HoverHandler {
        id: cardHover
    }

    /// One of the three controls: a rounded rectangle that tightens its corners while
    /// pressed. All three share the height, so the row reads as one bar.
    component Control: RippleButton {
        id: control
        property string symbol: ""
        property string label: ""
        property color colContent: ClockStyle.colOnSecondaryContainer
        property string tip: ""

        Layout.fillHeight: true
        buttonRadius: Math.min(control.height / 2, ClockStyle.radiusLarge)
        buttonRadiusPressed: ClockStyle.radiusSmall
        colBackground: ClockStyle.colSecondaryContainer
        colBackgroundHover: ClockStyle.colSecondaryContainerHover
        colRipple: ClockStyle.colSecondaryContainerActive

        contentItem: Item {
            implicitWidth: controlRow.implicitWidth
            implicitHeight: controlRow.implicitHeight

            RowLayout {
                id: controlRow
                anchors.centerIn: parent
                spacing: 6

                MaterialSymbol {
                    visible: control.symbol.length > 0
                    text: control.symbol
                    iconSize: ClockStyle.iconNormal
                    fill: 1
                    color: control.colContent
                    animateChange: !ClockStyle.reducedMotion
                }

                StyledText {
                    visible: control.label.length > 0
                    text: control.label
                    font.family: ClockStyle.fontMain
                    font.variableAxes: ClockStyle.axesDigitsBold
                    font.pixelSize: ClockStyle.textLarge
                    color: control.colContent
                }
            }
        }

        StyledToolTip {
            text: control.tip
            extraVisibleCondition: control.tip.length > 0
        }
    }

    RowLayout {
        anchors {
            fill: parent
            margins: ClockStyle.cardPadding
        }
        spacing: ClockStyle.cardPadding

        // ── Ring ────────────────────────────────────────────────────────
        Item {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: root.ringSize
            implicitHeight: root.ringSize

            ClockProgressRing {
                anchors.fill: parent
                value: root.finished ? 1 : root.progress
                thickness: root.ringThickness
                wavy: root.running
                tickDuration: root.running ? 1000 : 0
                colIndicator: root.colRing
                colTrack: root.colTrack
            }

            MaterialShapeWrappedMaterialSymbol {
                anchors.centerIn: parent
                text: root.finished ? "notifications_active" : root.paused ? "pause" : "hourglass_top"
                iconSize: root.ringSize * 0.2
                padding: root.ringSize * 0.1
                fill: 1
                shape: root.running ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Circle
                color: root.finished ? ClockStyle.colError : root.running ? ClockStyle.colPrimaryContainer : ClockStyle.colSecondaryContainer
                colSymbol: root.finished ? ClockStyle.colOnError : root.running ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSecondaryContainer
                animateChange: !ClockStyle.reducedMotion
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // ── Label and hover actions ─────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                implicitHeight: 32
                spacing: ClockStyle.gapSmall

                StyledText {
                    id: labelText
                    Layout.fillWidth: true
                    text: String(root.countdown?.label ?? Translation.tr("Timer"))
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textNormal
                    font.weight: Font.DemiBold
                    color: root.colContent

                    HoverHandler {
                        id: labelHover
                    }
                    StyledToolTip {
                        extraVisibleCondition: labelHover.hovered && labelText.truncated
                        text: labelText.text
                    }
                }

                Item {
                    id: actionSlot
                    property real revealProgress: root.engaged ? 1 : 0

                    Layout.preferredWidth: (actionRow.implicitWidth + 4) * actionSlot.revealProgress
                    Layout.preferredHeight: actionRow.implicitHeight
                    clip: true

                    Behavior on revealProgress {
                        animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                    }

                    RowLayout {
                        id: actionRow
                        anchors.left: parent.left
                        anchors.leftMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        opacity: actionSlot.revealProgress
                        enabled: root.engaged

                        ClockCardAction {
                            id: renameButton
                            symbol: "edit"
                            tip: Translation.tr("Rename")
                            colContent: root.colContent
                            onClicked: root.renameRequested()
                        }

                        ClockCardAction {
                            id: deleteButton
                            symbol: "delete"
                            tip: Translation.tr("Delete")
                            danger: true
                            onClicked: TimerService.removeCountdown(root.countdownId)
                        }
                    }
                }
            }

            // ── Time ────────────────────────────────────────────────────
            Item {
                Layout.fillHeight: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                StyledText {
                    text: root.finished ? Translation.tr("Time's up") : ClockFormat.duration(root.secondsLeft)
                    font.family: ClockStyle.fontMain
                    font.variableAxes: ClockStyle.axesDigitsBold
                    font.pixelSize: root.finished ? root.timeSize * 0.7 : root.timeSize
                    color: root.colContent
                }

                StyledText {
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: root.timeSize * 0.16
                    Layout.fillWidth: true
                    text: root.paused ? Translation.tr("Paused") : Translation.tr("of %1").arg(ClockFormat.shortDuration(root.countdown?.durationSeconds ?? 0))
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textNormal
                    color: root.colContent
                    opacity: 0.7
                }
            }

            Item {
                Layout.fillHeight: true
            }

            // ── Controls ────────────────────────────────────────────────
            // The side controls share one width, so the middle one sits on the row's
            // exact centre whatever the labels say.
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: root.controlHeight
                spacing: ClockStyle.gapSmall

                Control {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    Layout.horizontalStretchFactor: 2
                    label: "+1:00"
                    tip: Translation.tr("Add a minute")
                    onClicked: TimerService.extendCountdown(root.countdownId, 60)
                }

                Control {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    Layout.horizontalStretchFactor: 3
                    symbol: root.running ? "pause" : root.finished ? "replay" : "play_arrow"
                    tip: root.running ? Translation.tr("Pause") : Translation.tr("Start")
                    buttonRadius: root.running ? ClockStyle.radiusNormal : Math.min(height / 2, ClockStyle.radiusLarge)
                    colBackground: root.running ? ClockStyle.colPrimaryContainer : ClockStyle.colPrimary
                    colBackgroundHover: root.running ? ClockStyle.colPrimaryContainerHover : ClockStyle.colPrimaryHover
                    colRipple: root.running ? ClockStyle.colPrimaryContainerActive : ClockStyle.colPrimaryActive
                    colContent: root.running ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnPrimary
                    onClicked: {
                        if (root.finished)
                            TimerService.restartCountdown(root.countdownId);
                        else
                            TimerService.toggleCountdown(root.countdownId);
                    }
                }

                Control {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    Layout.horizontalStretchFactor: 2
                    symbol: "restart_alt"
                    tip: Translation.tr("Reset")
                    onClicked: {
                        TimerService.restartCountdown(root.countdownId);
                        TimerService.pauseCountdown(root.countdownId);
                    }
                }
            }
        }
    }
}
