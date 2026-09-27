pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Stopwatch: the elapsed time in giant digits on a scalloped shape that turns like a
 * seconds hand — one turn a minute, driven by the elapsed time itself, so it is as smooth
 * as the ten-millisecond clock under it and stops dead the moment you pause. The shape
 * never swaps for another; running and paused differ in colour only. Reset / start-pause
 * / lap underneath, and the laps on a pane of their own with the fastest and slowest
 * marked.
 */
Item {
    id: root

    property bool compact: false
    property bool wide: false
    property real layoutWidth: root.width

    // ── Tokens ──────────────────────────────────────────────────────────
    readonly property real padding: ClockStyle.gapTiny
    readonly property bool hasLaps: root.lapCount > 0
    readonly property bool sideBySide: root.layoutWidth >= ClockStyle.mediumMax - 80
    readonly property real lapsWidth: Math.round(Math.max(300, Math.min(root.layoutWidth * 0.34, 420)))
    readonly property real stageWidth: root.sideBySide && root.hasLaps ? root.layoutWidth - root.lapsWidth - ClockStyle.paneGap : root.layoutWidth
    readonly property real dialSize: Math.round(Math.max(ClockStyle.worldDialMin, Math.min(root.stageWidth - ClockStyle.gapHuge * 2,
        (root.sideBySide || !root.hasLaps ? root.height : root.height * 0.62) - ClockStyle.fabSizeLarge - ClockStyle.gapHuge * 4)))
    readonly property real digitSize: root.dialSize * 0.2
    readonly property color colShape: root.running ? ClockStyle.colPrimaryContainer : ClockStyle.colSecondaryContainer
    readonly property color colOnShape: root.running ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSecondaryContainer
    readonly property color colDot: ClockStyle.colPrimary
    readonly property color colFastest: ClockStyle.colPrimary
    readonly property color colSlowest: ClockStyle.colError

    readonly property bool running: TimerService.stopwatchRunning
    readonly property int elapsed: TimerService.stopwatchTime
    readonly property bool started: root.running || root.elapsed > 0
    readonly property var laps: Array.from(TimerService.stopwatchLaps ?? [])
    readonly property int lapCount: root.laps.length
    readonly property var lapDurations: root.laps.map((total, i) => total - (i > 0 ? root.laps[i - 1] : 0))
    readonly property int fastest: root.lapDurations.length > 1 ? root.lapDurations.indexOf(Math.min(...root.lapDurations)) : -1
    readonly property int slowest: root.lapDurations.length > 1 ? root.lapDurations.indexOf(Math.max(...root.lapDurations)) : -1
    readonly property var display: ClockFormat.stopwatch(root.elapsed)

    readonly property string pageSubtitle: root.lapCount > 0 ? Translation.tr("%1 laps").arg(String(root.lapCount)) : ""

    focus: true
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Space) {
            TimerService.toggleStopwatch();
            event.accepted = true;
        } else if (event.key === Qt.Key_L && root.running) {
            TimerService.stopwatchRecordLap();
            event.accepted = true;
        } else if (event.key === Qt.Key_R && !root.running) {
            TimerService.stopwatchReset();
            event.accepted = true;
        }
    }

    component Dial: Item {
        implicitWidth: root.dialSize
        implicitHeight: root.dialSize

        // The laps pane opening beside it shrinks the dial with the same motion.
        Behavior on implicitWidth {
            animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
        }
        Behavior on implicitHeight {
            animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
        }

        // Seconds within the minute, as degrees: the shape and its marker turn together.
        readonly property real sweep: ((root.elapsed % 6000) / 6000) * 360

        Item {
            anchors.fill: parent
            rotation: parent.sweep

            MaterialShape {
                anchors.fill: parent
                shapeString: "Cookie12Sided"
                color: root.colShape

                Behavior on color {
                    animation: ClockStyle.motionFast.colorAnimation.createObject(this)
                }
            }

            Rectangle {
                visible: root.started
                width: root.dialSize * 0.05
                height: width
                radius: width / 2
                anchors.horizontalCenter: parent.horizontalCenter
                y: root.dialSize * 0.07
                color: ClockStyle.colPrimary
            }
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 0

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: root.display.main
                font.family: ClockStyle.fontMain
                font.variableAxes: ClockStyle.axesDigitsBold
                font.pixelSize: root.elapsed >= 360000 ? root.digitSize * 0.78 : root.digitSize
                color: root.colOnShape
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: root.display.fraction
                font.family: ClockStyle.fontMain
                font.variableAxes: ClockStyle.axesDigits
                font.pixelSize: root.digitSize * 0.42
                color: root.colOnShape
                opacity: 0.75
            }
        }
    }

    component Controls: RowLayout {
        spacing: ClockStyle.gapLarge

        ClockIconButton {
            symbol: "restart_alt"
            tooltip: Translation.tr("Reset")
            size: ClockStyle.fabSize
            iconSize: ClockStyle.iconLarge
            colBackground: ClockStyle.colSecondaryContainer
            colIcon: ClockStyle.colOnSecondaryContainer
            enabled: !root.running && root.started
            opacity: enabled ? 1 : 0.35
            onClicked: TimerService.stopwatchReset()
        }

        ClockPlayButton {
            running: root.running
            onClicked: TimerService.toggleStopwatch()
        }

        ClockIconButton {
            symbol: "flag"
            tooltip: Translation.tr("Lap")
            size: ClockStyle.fabSize
            iconSize: ClockStyle.iconLarge
            colBackground: ClockStyle.colSecondaryContainer
            colIcon: ClockStyle.colOnSecondaryContainer
            enabled: root.running
            opacity: enabled ? 1 : 0.35
            onClicked: TimerService.stopwatchRecordLap()
        }
    }

    component LapList: ListView {
        clip: true
        spacing: 2
        model: root.lapCount
        boundsBehavior: Flickable.StopAtBounds

        delegate: Rectangle {
            id: lap
            required property int index
            readonly property int lapIndex: root.lapCount - 1 - lap.index
            readonly property bool isFastest: lap.lapIndex === root.fastest
            readonly property bool isSlowest: lap.lapIndex === root.slowest
            readonly property color colAccent: lap.isFastest ? ClockStyle.colOnPrimaryContainer : lap.isSlowest ? ClockStyle.colOnErrorContainer : ClockStyle.colOnSurface

            width: ListView.view.width
            implicitHeight: ClockStyle.rowHeight
            radius: Appearance.rounding.small
            color: lap.isFastest ? ClockStyle.colPrimaryContainer : lap.isSlowest ? ClockStyle.colErrorContainer : ClockStyle.colField

            StaggeredEntrance {
                index: 0
                active: !ClockStyle.reducedMotion && lap.index === 0
            }

            RowLayout {
                anchors {
                    fill: parent
                    leftMargin: ClockStyle.cardPadding
                    rightMargin: ClockStyle.cardPadding
                }
                spacing: ClockStyle.gapLarge

                MaterialSymbol {
                    text: lap.isFastest ? "bolt" : lap.isSlowest ? "hourglass_bottom" : "flag"
                    iconSize: ClockStyle.iconSmall
                    fill: lap.isFastest || lap.isSlowest ? 1 : 0
                    color: lap.colAccent
                }

                StyledText {
                    text: Translation.tr("Lap %1").arg(String(lap.lapIndex + 1))
                    font.pixelSize: ClockStyle.textNormal
                    color: lap.colAccent
                    opacity: 0.8
                }

                Item {
                    Layout.fillWidth: true
                }

                StyledText {
                    text: {
                        const part = ClockFormat.stopwatch(root.lapDurations[lap.lapIndex] ?? 0);
                        return part.main + "." + part.fraction;
                    }
                    font.family: ClockStyle.fontMain
                    font.variableAxes: ClockStyle.axesDigitsBold
                    font.pixelSize: ClockStyle.textLarge + 2
                    color: lap.colAccent
                }

                StyledText {
                    text: {
                        const part = ClockFormat.stopwatch(root.laps[lap.lapIndex] ?? 0);
                        return part.main + "." + part.fraction;
                    }
                    font.family: ClockStyle.fontMain
                    font.variableAxes: ClockStyle.axesDigits
                    font.pixelSize: ClockStyle.textNormal
                    color: lap.colAccent
                    opacity: 0.7
                }
            }
        }
    }

    component LapsPane: Rectangle {
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colPane

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Laps")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.Bold
                    color: ClockStyle.colOnSurface
                }

                StyledText {
                    visible: root.lapCount > 0
                    text: String(root.lapCount)
                    font.family: ClockStyle.fontMain
                    font.variableAxes: ClockStyle.axesDigitsBold
                    font.pixelSize: ClockStyle.textLarge
                    color: ClockStyle.colPrimary
                }
            }

            LapList {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }
    }

    component Stage: Rectangle {
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colPane

        ColumnLayout {
            anchors.centerIn: parent
            spacing: ClockStyle.gapHuge

            Dial {
                Layout.alignment: Qt.AlignHCenter
            }
            Controls {
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: root.sideBySide
        sourceComponent: RowLayout {
            spacing: ClockStyle.paneGap

            Stage {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }

            // Only once there is a lap to show: an empty pane beside the dial was a third
            // of the window saying nothing.
            Item {
                Layout.fillHeight: true
                Layout.preferredWidth: root.hasLaps ? root.lapsWidth : 0
                Layout.leftMargin: root.hasLaps ? 0 : -ClockStyle.paneGap
                visible: Layout.preferredWidth > 1
                clip: true

                Behavior on Layout.preferredWidth {
                    animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                }
                Behavior on Layout.leftMargin {
                    animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                }

                LapsPane {
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    width: root.lapsWidth
                }
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: !root.sideBySide
        sourceComponent: ColumnLayout {
            spacing: ClockStyle.paneGap

            Stage {
                Layout.fillWidth: true
                Layout.fillHeight: !root.hasLaps
                Layout.preferredHeight: root.dialSize + ClockStyle.fabSizeLarge + ClockStyle.gapHuge * 3
            }

            LapsPane {
                visible: root.hasLaps
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }
    }
}
