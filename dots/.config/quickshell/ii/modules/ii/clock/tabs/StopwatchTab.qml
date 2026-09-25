pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Stopwatch: the elapsed time in giant digits inside a soft-burst shape whose seconds
 * dot sweeps the rim, reset / start-pause / lap underneath, and the laps with the fastest
 * and slowest marked. Display left and laps right on a wide window.
 */
Item {
    id: root

    property bool compact: false
    property bool wide: false

    // ── Tokens ──────────────────────────────────────────────────────────
    readonly property real padding: root.compact ? ClockStyle.pagePadding : ClockStyle.pagePaddingWide
    readonly property bool sideBySide: root.width >= ClockStyle.mediumMax && root.lapCount > 0
    readonly property real dialSize: Math.max(ClockStyle.worldDialMin, Math.min(
        root.sideBySide ? root.width * 0.42 : root.width - root.padding * 2,
        root.height - ClockStyle.fabSizeLarge - ClockStyle.gapHuge * 3 - (root.lapCount > 0 && !root.sideBySide ? root.height * 0.3 : 0)))
    readonly property real digitSize: root.dialSize * 0.22
    readonly property color colShape: ClockStyle.colPrimaryContainer
    readonly property color colOnShape: ClockStyle.colOnPrimaryContainer
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

        MaterialShape {
            anchors.fill: parent
            shapeString: root.running ? "SoftBurst" : "Cookie12Sided"
            color: root.colShape
        }

        Rectangle {
            readonly property real radians: ((root.elapsed % 6000) / 6000) * 2 * Math.PI
            readonly property real distance: root.dialSize * 0.41
            visible: root.started
            width: root.dialSize * 0.045
            height: width
            radius: width / 2
            color: root.colDot
            x: parent.width / 2 + distance * Math.sin(radians) - width / 2
            y: parent.height / 2 - distance * Math.cos(radians) - height / 2
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
            colBackground: ClockStyle.colSurfaceHighest
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
            colBackground: ClockStyle.colSurfaceHighest
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
            readonly property color colAccent: lap.isFastest ? root.colFastest : lap.isSlowest ? root.colSlowest : ClockStyle.colOnSurface

            width: ListView.view.width
            implicitHeight: ClockStyle.topBarHeight - ClockStyle.gapSmall
            radius: lap.index === 0 ? ClockStyle.radiusLarge : ClockStyle.radiusSmall / 2
            bottomLeftRadius: lap.index === root.lapCount - 1 ? ClockStyle.radiusLarge : ClockStyle.radiusSmall / 2
            bottomRightRadius: lap.index === root.lapCount - 1 ? ClockStyle.radiusLarge : ClockStyle.radiusSmall / 2
            color: ClockStyle.colSurfaceHigh

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
                    color: ClockStyle.colOnSurfaceVariant
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
                    color: ClockStyle.colSubtext
                }
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: root.sideBySide
        sourceComponent: RowLayout {
            spacing: ClockStyle.gapHuge

            ColumnLayout {
                Layout.fillHeight: true
                Layout.preferredWidth: root.width * 0.46
                Layout.leftMargin: root.padding
                spacing: ClockStyle.gapHuge

                Item {
                    Layout.fillHeight: true
                }
                Dial {
                    Layout.alignment: Qt.AlignHCenter
                }
                Controls {
                    Layout.alignment: Qt.AlignHCenter
                }
                Item {
                    Layout.fillHeight: true
                }
            }

            LapList {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.topMargin: ClockStyle.gapSmall
                Layout.bottomMargin: root.padding
                Layout.rightMargin: root.padding
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: !root.sideBySide
        sourceComponent: ColumnLayout {
            spacing: ClockStyle.gapHuge

            Item {
                Layout.fillHeight: root.lapCount === 0
                Layout.preferredHeight: ClockStyle.gapSmall
            }
            Dial {
                Layout.alignment: Qt.AlignHCenter
            }
            Controls {
                Layout.alignment: Qt.AlignHCenter
            }
            LapList {
                visible: root.lapCount > 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: root.padding
                Layout.rightMargin: root.padding
                Layout.bottomMargin: root.padding
            }
            Item {
                visible: root.lapCount === 0
                Layout.fillHeight: true
            }
        }
    }
}
