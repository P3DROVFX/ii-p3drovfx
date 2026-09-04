pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

/**
 * Material 3 Expressive Timer widget.
 *
 * Each active timer is a separate tonal capsule with an organic mode marker.
 * This keeps Pomodoro, stopwatch, and countdown independently actionable while
 * making their hierarchy legible through shape, weight, and colour.
 */
Item {
    id: root

    property bool vertical: false

    readonly property bool compVisible: timerState.visible
    readonly property real thickness: root.vertical
        ? Appearance.sizes.verticalBarWidth - 8
        : Appearance.sizes.baseBarHeight - 8
    readonly property int contentRotation: root.vertical
        ? (Config.options.bar.bottom ? 90 : -90)
        : 0
    readonly property real targetLength: root.vertical
        ? readoutLayout.implicitHeight
        : readoutLayout.implicitWidth
    property real animatedLength: root.targetLength

    visible: root.compVisible
    clip: true
    implicitWidth: root.compVisible
        ? (root.vertical ? Appearance.sizes.verticalBarWidth : root.animatedLength)
        : 0
    implicitHeight: root.compVisible
        ? (root.vertical ? root.animatedLength : Appearance.sizes.baseBarHeight)
        : 0

    function syncBarVisibility() {
        if (typeof rootItem !== "undefined" && rootItem?.toggleVisible)
            rootItem.toggleVisible(root.compVisible);
    }

    onCompVisibleChanged: root.syncBarVisibility()
    Component.onCompleted: root.syncBarVisibility()

    Behavior on animatedLength {
        animation: Appearance.animation.barResize.numberAnimation.createObject(root)
    }

    TimerBarState {
        id: timerState
    }

    BarWidgetPalette {
        id: theme
        colorMode: "tonal"
    }

    GridLayout {
        id: readoutLayout
        anchors.centerIn: parent
        columns: root.vertical ? 1 : 3
        rows: root.vertical ? 3 : 1
        rowSpacing: 4
        columnSpacing: 4

        Loader {
            active: timerState.showStopwatch && timerState.hasStopwatch
            visible: active
            Layout.alignment: Qt.AlignCenter
            sourceComponent: ExpressiveReadout {
                vertical: root.vertical
                thickness: root.thickness
                contentRotation: root.contentRotation
                iconName: timerState.stopwatchRunning ? "timer" : "timer_pause"
                value: timerState.stopwatchText
                markerShape: MaterialShape.Shape.Circle
                tooltip: timerState.stopwatchRunning
                    ? Translation.tr("Pause stopwatch")
                    : Translation.tr("Resume stopwatch")
                onTriggered: TimerService.toggleStopwatch()
            }
        }

        Loader {
            active: timerState.showPomodoro && timerState.hasPomodoro
            visible: active
            Layout.alignment: Qt.AlignCenter
            sourceComponent: ExpressiveReadout {
                vertical: root.vertical
                thickness: root.thickness
                contentRotation: root.contentRotation
                iconName: timerState.pomodoroRunning ? "search_activity" : "pause_circle"
                value: timerState.pomodoroText
                markerShape: MaterialShape.Shape.Cookie9Sided
                tooltip: timerState.pomodoroRunning
                    ? Translation.tr("Pause pomodoro")
                    : Translation.tr("Resume pomodoro")
                onTriggered: TimerService.togglePomodoro()
            }
        }

        Loader {
            active: timerState.showCountdowns && timerState.hasCountdown
            visible: active
            Layout.alignment: Qt.AlignCenter
            sourceComponent: ExpressiveReadout {
                vertical: root.vertical
                thickness: root.thickness
                contentRotation: root.contentRotation
                iconName: timerState.countdownPaused ? "pause_circle" : "hourglass_top"
                value: timerState.countdownText
                badgeCount: timerState.countdownCount
                markerShape: MaterialShape.Shape.Arch
                tooltip: timerState.countdownTooltip
                onTriggered: timerState.toggleCountdown()
            }
        }
    }

    component ExpressiveReadout: RippleButton {
        id: readout

        property bool vertical: false
        property real thickness: 0
        property int contentRotation: 0
        property string iconName: ""
        property string value: ""
        property string tooltip: ""
        property int badgeCount: 0
        property int markerShape: MaterialShape.Shape.Circle
        signal triggered

        implicitWidth: readout.vertical
            ? readout.thickness
            : content.implicitWidth + 12
        implicitHeight: readout.vertical
            ? content.implicitHeight + 12
            : readout.thickness

        buttonRadius: Config.options.bar.barGroupStyle === 1
            ? Appearance.rounding.windowRounding
            : Appearance.rounding.full
        colBackground: theme.container
        colBackgroundHover: Appearance.colors.colTertiaryContainerHover
        colBackgroundActive: Appearance.colors.colTertiaryContainerActive
        colRipple: Appearance.colors.colTertiaryContainerActive
        onPressed: readout.triggered()

        GridLayout {
            id: content
            anchors.centerIn: parent
            columns: readout.vertical ? 1 : (readout.badgeCount > 1 ? 3 : 2)
            rows: readout.vertical ? (readout.badgeCount > 1 ? 3 : 2) : 1
            rowSpacing: 4
            columnSpacing: 6

            MaterialShapeWrappedMaterialSymbol {
                Layout.alignment: Qt.AlignCenter
                shape: readout.markerShape
                implicitSize: readout.thickness - 10
                iconSize: Appearance.font.pixelSize.normal
                padding: 3
                text: readout.iconName
                color: theme.accent
                colSymbol: theme.onAccent
            }

            Item {
                id: timeHolder
                Layout.alignment: Qt.AlignCenter
                implicitWidth: readout.vertical ? timeText.implicitHeight : timeText.implicitWidth
                implicitHeight: readout.vertical ? timeText.implicitWidth : timeText.implicitHeight

                StyledText {
                    id: timeText
                    anchors.centerIn: parent
                    rotation: readout.contentRotation
                    text: readout.value
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    font.features: ({ "tnum": 1 })
                    color: ColorUtils.categoryOnColor(theme.container)
                }
            }

            Rectangle {
                visible: readout.badgeCount > 1
                Layout.alignment: Qt.AlignCenter
                implicitWidth: 18
                implicitHeight: 18
                radius: Appearance.rounding.full
                color: theme.accent

                StyledText {
                    anchors.centerIn: parent
                    text: String(readout.badgeCount)
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: theme.onAccent
                }
            }
        }

        StyledToolTip {
            text: readout.tooltip
            requireOverlay: false
        }
    }
}
