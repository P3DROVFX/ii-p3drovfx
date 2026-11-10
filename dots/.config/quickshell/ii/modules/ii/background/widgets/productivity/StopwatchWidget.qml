import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets

/*
 * Stopwatch (1x1). The elapsed time fills the top in tall condensed digits
 * with the hundredths in monospace beside them. The start key is the dial
 * itself: a scalloped shape that turns once a minute with the elapsed time,
 * in the accent while it runs. Lap and reset sit beside it.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "timer_stopwatch"
    designWidth: 240
    designHeight: 240

    readonly property real padding: 16
    readonly property real dialSize: 84
    readonly property real digitSize: 92

    readonly property bool running: TimerService.stopwatchRunning
    readonly property var laps: TimerService.stopwatchLaps ?? []
    // The service counts in 10 ms; the face only needs a tenth of that, and
    // nothing at all while it is not running.
    property int shownTime: TimerService.stopwatchTime
    Timer {
        interval: 100
        repeat: true
        running: root.running && root.live
        onTriggered: root.shownTime = TimerService.stopwatchTime
    }
    Connections {
        target: TimerService
        enabled: !root.running
        function onStopwatchTimeChanged() {
            root.shownTime = TimerService.stopwatchTime;
        }
    }

    readonly property int totalSeconds: Math.floor(root.shownTime / 100)
    readonly property string mainText: {
        const hours = Math.floor(root.totalSeconds / 3600);
        const minutes = Math.floor((root.totalSeconds % 3600) / 60);
        const seconds = root.totalSeconds % 60;
        const tail = String(minutes).padStart(2, "0") + ":" + String(seconds).padStart(2, "0");
        return hours > 0 ? hours + ":" + tail : tail;
    }
    readonly property string hundredths: String(Math.floor(root.shownTime % 100)).padStart(2, "0")
    readonly property bool started: root.shownTime > 0

    // ── Caption + laps ──
    StyledText {
        x: root.padding + 2
        y: root.padding
        text: Translation.tr("Stopwatch").toUpperCase()
        color: WidgetColorScheme.subtextColorOnBg
        font.family: Appearance.font.family.monospace
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.letterSpacing: 1.5
    }

    Rectangle {
        visible: root.laps.length > 0
        anchors.right: parent.right
        anchors.rightMargin: root.padding
        y: root.padding - 4
        width: lapText.implicitWidth + 18
        height: 24
        radius: root.pill(height)
        color: WidgetColorScheme.pillBgColor

        StyledText {
            id: lapText
            anchors.centerIn: parent
            text: Translation.tr("Lap %1").arg(root.laps.length)
            color: WidgetColorScheme.textColorOnBg
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }

    // ── Time ──
    Row {
        x: root.padding - 2
        y: 34
        spacing: 2

        Text {
            id: digits
            text: root.mainText
            color: root.started ? WidgetColorScheme.textColorOnBg : WidgetColorScheme.subtextColorOnBg
            font.family: Appearance.font.family.main
            // Hours push the line wider: give them room by shrinking, not clipping.
            font.pixelSize: root.totalSeconds >= 3600 ? Math.round(root.digitSize * 0.72) : root.digitSize
            font.variableAxes: ({ "wght": root.running ? 760 : 560, "wdth": 40, "ROND": 100, "opsz": 144 })
            renderType: Text.QtRendering
        }

        StyledText {
            anchors.baseline: digits.baseline
            text: root.hundredths
            color: WidgetColorScheme.accentColor
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.huge
        }
    }

    // ── Dial key ──
    Item {
        id: dial
        x: root.padding
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.padding
        width: root.dialSize
        height: root.dialSize

        MaterialShape {
            anchors.fill: parent
            shape: dialHover.hovered && root.actionsEnabled ? MaterialShape.Shape.Cookie12Sided : MaterialShape.Shape.Cookie9Sided
            color: root.running ? WidgetColorScheme.accentColor
                : root.started ? WidgetColorScheme.pillFillColor : WidgetColorScheme.pillBgColor
            // One turn a minute with the elapsed time.
            rotation: (root.shownTime % 6000) / 6000 * 360

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: root.running ? "pause" : "play_arrow"
            iconSize: 36
            fill: 1
            color: root.running ? WidgetColorScheme.onAccentColor
                : root.started ? WidgetColorScheme.textColorOnPillFill : WidgetColorScheme.textColorOnBg
        }

        HoverHandler {
            id: dialHover
            enabled: root.actionsEnabled
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            enabled: root.actionsEnabled
            onTapped: TimerService.toggleStopwatch()
        }
    }

    // ── Lap / reset ──
    Column {
        anchors.left: dial.right
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.rightMargin: root.padding
        anchors.verticalCenter: dial.verticalCenter
        spacing: 6

        WidgetButton {
            width: parent.width
            height: 39
            enabled: root.running
            symbol: "flag"
            symbolSize: 18
            label: Translation.tr("Lap")
            colFill: WidgetColorScheme.pillBgColor
            colContent: WidgetColorScheme.textColorOnBg
            onClicked: TimerService.stopwatchRecordLap()
        }

        WidgetButton {
            width: parent.width
            height: 39
            enabled: root.started && !root.running
            symbol: "restart_alt"
            symbolSize: 18
            label: Translation.tr("Reset")
            colFill: WidgetColorScheme.pillBgColor
            colContent: WidgetColorScheme.textColorOnBg
            onClicked: TimerService.stopwatchReset()
        }
    }
}
