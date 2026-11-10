import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components

/**
 * Stopwatch. Square: at rest a scalloped dial with the stopwatch glyph; once
 * started, the elapsed time in condensed digits over the dial, which turns one
 * revolution a minute. A click starts or pauses. Wide: the play control (a
 * circle, a rounded square while running), the time over "lap n · split", and
 * lap / reset. The panel holds the laps.
 */
UtilityTile {
    id: tile

    readonly property bool running: TimerService.stopwatchRunning
    readonly property int centiseconds: TimerService.stopwatchTime
    readonly property int seconds: Math.floor(tile.centiseconds / 100)
    readonly property bool started: tile.running || tile.centiseconds > 0
    readonly property var laps: TimerService.stopwatchLaps ?? []
    readonly property string mainText: ClockFormat.stopwatch(tile.centiseconds).main
    // Square text: "m:ss" under an hour, "h:mm" beyond (seconds no longer fit).
    readonly property string shortText: tile.seconds >= 3600
        ? Math.floor(tile.seconds / 3600) + "h" + ClockFormat.pad(Math.floor((tile.seconds % 3600) / 60))
        : Math.floor(tile.seconds / 60) + ":" + ClockFormat.pad(tile.seconds % 60)
    readonly property int currentLap: tile.centiseconds - (tile.laps.length > 0 ? tile.laps[tile.laps.length - 1] : 0)
    readonly property bool clickToggles: Config.options?.dock?.utilities?.stopwatch?.clickToggles ?? true

    surfaceColor: tile.running ? ClockStyle.colPrimaryContainer
        : tile.started ? ClockStyle.colSecondaryContainer
        : ClockStyle.colSurfaceHigh
    contentColor: tile.running ? ClockStyle.colOnPrimaryContainer
        : tile.started ? ClockStyle.colOnSecondaryContainer
        : ClockStyle.colOnSurface

    tooltipText: tile.started
        ? Translation.tr("Stopwatch · %1").arg(tile.mainText) + (tile.laps.length > 0 ? " · " + Translation.tr("%1 laps").arg(tile.laps.length) : "")
        : Translation.tr("Stopwatch")
    panelSubtitle: tile.running ? Translation.tr("Running") : tile.started ? Translation.tr("Paused") : Translation.tr("Ready")
    menuActions: [
        { id: "toggle", icon: tile.running ? "pause" : "play_arrow", text: tile.running ? Translation.tr("Pause") : Translation.tr("Start") },
        { id: "lap", icon: "flag", text: Translation.tr("Lap"), visible: tile.running },
        { id: "reset", icon: "restart_alt", text: Translation.tr("Reset"), visible: tile.started && !tile.running }
    ]

    function activate() {
        if (tile.wide || !tile.clickToggles)
            return false;
        TimerService.toggleStopwatch();
        return true;
    }

    function menuAction(actionId) {
        if (actionId === "toggle")
            TimerService.toggleStopwatch();
        else if (actionId === "lap")
            TimerService.stopwatchRecordLap();
        else if (actionId === "reset")
            TimerService.stopwatchReset();
    }

    // ── Square ──────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        visible: !tile.wide

        // Turns with elapsed seconds, each step gliding over its second.
        TileShape {
            anchors.centerIn: parent
            width: Math.round(tile.side * (tile.started ? 0.9 : 0.74))
            height: width
            renderScale: tile.renderScale
            shape: MaterialShape.Shape.Cookie12Sided
            color: tile.started ? ColorUtils.applyAlpha(tile.contentColor, 0.12) : ClockStyle.colPrimaryContainer
            rotation: tile.seconds * 6
            Behavior on rotation {
                enabled: !Appearance.reducedMotion && tile.running
                NumberAnimation { duration: 1000; easing.type: Easing.Linear }
            }
            Behavior on width {
                animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
            }
        }
        TileSymbol {
            anchors.centerIn: parent
            visible: !tile.started
            text: "timer"
            iconSize: Math.round(tile.side * 0.4)
            fill: 1
            color: ClockStyle.colOnPrimaryContainer
        }
        TileValue {
            anchors.centerIn: parent
            visible: tile.started
            text: tile.shortText
            color: tile.contentColor
            font.pixelSize: Math.round(tile.side * (tile.shortText.length > 4 ? 0.32 : 0.38))
        }
    }

    // ── Wide ────────────────────────────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        anchors.margins: tile.pad
        visible: tile.wide
        spacing: tile.pad

        TileButton {
            implicitWidth: tile.badgeSize
            implicitHeight: tile.badgeSize
            symbol: tile.running ? "pause" : "play_arrow"
            filled: true
            active: tile.running
            iconScale: 0.52
            onClicked: TimerService.toggleStopwatch()
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: -2
            TileValue {
                Layout.fillWidth: true
                text: tile.mainText
                color: tile.contentColor
                font.pixelSize: tile.valueSize
            }
            TileCaption {
                Layout.fillWidth: true
                text: tile.laps.length > 0
                    ? Translation.tr("Lap %1 · %2").arg(tile.laps.length + 1).arg(ClockFormat.stopwatch(tile.currentLap).main)
                    : tile.running ? Translation.tr("Running") : tile.started ? Translation.tr("Paused") : Translation.tr("Stopwatch")
                color: tile.captionColor
                font.pixelSize: tile.captionSize
            }
        }

        TileButton {
            visible: tile.started
            implicitWidth: Math.round(tile.badgeSize * 0.84)
            implicitHeight: implicitWidth
            symbol: tile.running ? "flag" : "restart_alt"
            tip: tile.running ? Translation.tr("Lap") : Translation.tr("Reset")
            colContent: tile.contentColor
            onClicked: tile.running ? TimerService.stopwatchRecordLap() : TimerService.stopwatchReset()
        }
    }
}
